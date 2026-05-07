#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>
#include <stdbool.h>
#include <iostream>
#include <string>
#include <limits.h>

#define MAX_COLORS 256
#define NUM_RUNS 10
#define THREADS_PER_BLOCK 256

__device__ int find_available_color(int *neighbors, int num_neighbors, int *color, int v) {
    bool used_colors[MAX_COLORS] = {false};
    for (int i = 0; i < num_neighbors; i++) {
        int neighbor = neighbors[i];
        if (color[neighbor] != -1) used_colors[color[neighbor]] = true;
    }
    for (int c = 0; c < MAX_COLORS; c++) if (!used_colors[c]) return c;
    return MAX_COLORS;
}

__global__ void parallel_coloring_kernel(int *color, int *row_ptr, int *col_idx, int num_vertices) {
    int v = blockIdx.x * blockDim.x + threadIdx.x;
    if (v < num_vertices) {
        int neighbors_count = row_ptr[v + 1] - row_ptr[v];
        int *neighbors = &col_idx[row_ptr[v]];
        color[v] = find_available_color(neighbors, neighbors_count, color, v);
    }
}

__global__ void resolve_conflicts_kernel(int *color, int *row_ptr, int *col_idx, int num_vertices) {
    int v = blockIdx.x * blockDim.x + threadIdx.x;
    if (v < num_vertices) {
        int neighbors_count = row_ptr[v + 1] - row_ptr[v];
        int *neighbors = &col_idx[row_ptr[v]];
        for (int i = 0; i < neighbors_count; i++) {
            int u = neighbors[i];
            if (color[v] == color[u] && v > u) color[v] = -1;
        }
    }
}

__global__ void recolor_kernel(int *color, int *row_ptr, int *col_idx, int num_vertices) {
    int v = blockIdx.x * blockDim.x + threadIdx.x;
    if (v < num_vertices && color[v] == -1) {
        int neighbors_count = row_ptr[v + 1] - row_ptr[v];
        int *neighbors = &col_idx[row_ptr[v]];
        color[v] = find_available_color(neighbors, neighbors_count, color, v);
    }
}

void read_csr(const char *filename, int **row_ptr, int **col_idx, int *num_vertices, int *num_edges) {
    FILE *file = fopen(filename, "r");
    if (!file) { perror("Error opening CSR file"); exit(EXIT_FAILURE); }
    fscanf(file, "%d %d", num_vertices, num_edges);
    *row_ptr = (int *)malloc((*num_vertices + 1) * sizeof(int));
    *col_idx = (int *)malloc((*num_edges) * sizeof(int));
    for (int i = 0; i <= *num_vertices; i++) fscanf(file, "%d", &(*row_ptr)[i]);
    for (int i = 0; i < *num_edges; i++) fscanf(file, "%d", &(*col_idx)[i]);
    fclose(file);
}

void read_egr(const char *filename, int **row_ptr, int **col_idx, int *num_vertices, int *num_edges) {
    FILE *file = fopen(filename, "r");
    if (!file) { perror("Error opening EGR file"); exit(EXIT_FAILURE); }
    int src, dst;
    int max_vertex = -1;
    int edge_count = 0;
    while (fscanf(file, "%d %d", &src, &dst) == 2) {
        if (src > max_vertex) max_vertex = src;
        if (dst > max_vertex) max_vertex = dst;
        edge_count++;
    }
    *num_vertices = max_vertex + 1;
    *num_edges = edge_count;
    *row_ptr = (int *)calloc((*num_vertices + 1), sizeof(int));
    *col_idx = (int *)malloc((*num_edges) * sizeof(int));
    rewind(file);
    int edge_index = 0;
    while (fscanf(file, "%d %d", &src, &dst) == 2) {
        (*row_ptr)[src + 1]++;
        (*col_idx)[edge_index++] = dst;
    }
    for (int i = 1; i <= *num_vertices; i++) {
        (*row_ptr)[i] += (*row_ptr)[i - 1];
    }
    fclose(file);
}

int count_unique_colors(int *color, int num_vertices) {
    bool color_used[MAX_COLORS] = {false};
    int unique_colors = 0;
    for (int i = 0; i < num_vertices; i++) {
        if (color[i] != -1 && !color_used[color[i]]) {
            color_used[color[i]] = true;
            unique_colors++;
        }
    }
    return unique_colors;
}

void parallel_graph_coloring(int *row_ptr, int *col_idx, int num_vertices, int num_edges) {
    double total_time = 0.0;
    int *color = (int *)malloc(num_vertices * sizeof(int));
    int *d_color, *d_row_ptr, *d_col_idx;
    cudaMalloc(&d_color, num_vertices * sizeof(int));
    cudaMalloc(&d_row_ptr, (num_vertices + 1) * sizeof(int));
    cudaMalloc(&d_col_idx, num_edges * sizeof(int));
    cudaMemcpy(d_row_ptr, row_ptr, (num_vertices + 1) * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_col_idx, col_idx, num_edges * sizeof(int), cudaMemcpyHostToDevice);

    for (int r = 0; r < NUM_RUNS; r++) {
        for (int i = 0; i < num_vertices; i++) color[i] = -1;
        cudaMemcpy(d_color, color, num_vertices * sizeof(int), cudaMemcpyHostToDevice);
        cudaDeviceSynchronize();
        cudaEvent_t start, stop;
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
        cudaEventRecord(start);
        int blocks = (num_vertices + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;
        parallel_coloring_kernel<<<blocks, THREADS_PER_BLOCK>>>(d_color, d_row_ptr, d_col_idx, num_vertices);
        cudaDeviceSynchronize();
        resolve_conflicts_kernel<<<blocks, THREADS_PER_BLOCK>>>(d_color, d_row_ptr, d_col_idx, num_vertices);
        cudaDeviceSynchronize();
        recolor_kernel<<<blocks, THREADS_PER_BLOCK>>>(d_color, d_row_ptr, d_col_idx, num_vertices);
        cudaDeviceSynchronize();
        cudaEventRecord(stop);
        cudaEventSynchronize(stop);
        float ms = 0;
        cudaEventElapsedTime(&ms, start, stop);
        total_time += ms / 1000.0;
        cudaEventDestroy(start);
        cudaEventDestroy(stop);
    }
    cudaMemcpy(color, d_color, num_vertices * sizeof(int), cudaMemcpyDeviceToHost);
    double avg_time = total_time / NUM_RUNS;
    int unique_colors = count_unique_colors(color, num_vertices);
    printf("Total edges: %d\nTotal nodes: %d\nNo of colors used: %d\nAverage time in seconds: %.6f\nAverage throughput: %.6f nodes/sec\n", 
           num_edges, num_vertices, unique_colors, avg_time, num_vertices / avg_time);
    free(color);
    cudaFree(d_color);
    cudaFree(d_row_ptr);
    cudaFree(d_col_idx);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <input_file.csr>\n", argv[0]);
        return 1;
    }
    const char *file_path = argv[1];
    int *row_ptr, *col_idx, num_vertices, num_edges;
    read_csr(file_path, &row_ptr, &col_idx, &num_vertices, &num_edges);
    printf("Parallel Graph Coloring (CUDA):\n");
    parallel_graph_coloring(row_ptr, col_idx, num_vertices, num_edges);
    free(row_ptr);
    free(col_idx);
    return 0;
} 