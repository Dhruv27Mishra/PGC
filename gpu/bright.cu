#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>
#include <stdbool.h>
#include <iostream>
#include <string>
#include <limits.h>

#define MAX_COLORS 256
#define NUM_RUNS 10
#define THREADS_PER_BLOCK 512
#define MAX_BLOCK_BUCKET 1024

__device__ int find_available_color(int *neighbors, int num_neighbors, int *color, int v) {
    bool used_colors[MAX_COLORS] = {false};
    int min_color = MAX_COLORS;
    
    // First pass: find used colors and minimum available color
    for (int i = 0; i < num_neighbors; i++) {
        int neighbor = neighbors[i];
        if (color[neighbor] != -1) {
            used_colors[color[neighbor]] = true;
            min_color = min(min_color, color[neighbor]);
        }
    }
    
    // Try to reuse colors from neighbors first
    if (min_color < MAX_COLORS) {
        for (int c = 0; c < min_color; c++) {
            if (!used_colors[c]) return c;
        }
    }
    
    // If no reuse possible, find first available color
    for (int c = 0; c < MAX_COLORS; c++) {
        if (!used_colors[c]) return c;
    }
    return MAX_COLORS;
}

__global__ void parallel_coloring_kernel(int *color, int *row_ptr, int *col_idx, int num_vertices) {
    int v = blockIdx.x * blockDim.x + threadIdx.x;
    if (v < num_vertices) {
        int neighbors_count = row_ptr[v + 1] - row_ptr[v];
        int *neighbors = &col_idx[row_ptr[v]];
        
        // Skip if no neighbors
        if (neighbors_count == 0) {
            color[v] = 0;
            return;
        }
        
        color[v] = find_available_color(neighbors, neighbors_count, color, v);
    }
}

__global__ void conflict_detect_and_recolor_kernel(
    int *color, int *row_ptr, int *col_idx, int num_vertices, int *bucket, int *bucket_size) {
    extern __shared__ int shared_bucket[];
    __shared__ int shared_bucket_size;
    if (threadIdx.x == 0) shared_bucket_size = 0;
    __syncthreads();

    int v = blockIdx.x * blockDim.x + threadIdx.x;
    if (v < num_vertices) {
        int neighbors_count = row_ptr[v + 1] - row_ptr[v];
        int *neighbors = &col_idx[row_ptr[v]];
        int my_color = color[v];
        int conflict = 0;
        
        // Early exit if no neighbors
        if (neighbors_count == 0) return;
        
        // Process neighbors in chunks for better memory coalescing
        for (int i = 0; i < neighbors_count; i += 8) {
            int end = min(i + 8, neighbors_count);
            for (int j = i; j < end; j++) {
                int u = neighbors[j];
                if (my_color == color[u] && v > u) {
                    conflict = 1;
                    break;
                }
            }
            if (conflict) break;
        }
        
        if (conflict) {
            int idx = atomicAdd(&shared_bucket_size, 1);
            if (idx < MAX_BLOCK_BUCKET) shared_bucket[idx] = v;
        }
    }
    __syncthreads();
    
    // Merge per-block bucket to global bucket
    if (threadIdx.x == 0 && shared_bucket_size > 0) {
        int global_idx = atomicAdd(bucket_size, shared_bucket_size);
        for (int i = 0; i < shared_bucket_size; i++) {
            bucket[global_idx + i] = shared_bucket[i];
        }
    }
}

__global__ void fused_recolor_kernel(int *color, int *row_ptr, int *col_idx, int *bucket, int bucket_size) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < bucket_size) {
        int v = bucket[idx];
        int neighbors_count = row_ptr[v + 1] - row_ptr[v];
        int *neighbors = &col_idx[row_ptr[v]];
        
        // Early exit if no neighbors
        if (neighbors_count == 0) {
            color[v] = 0;
            return;
        }
        
        // Mark as uncolored if still in conflict
        int my_color = color[v];
        int conflict = 0;
        
        // Process neighbors in chunks for better memory coalescing
        for (int i = 0; i < neighbors_count; i += 8) {
            int end = min(i + 8, neighbors_count);
            for (int j = i; j < end; j++) {
                int u = neighbors[j];
                if (my_color == color[u] && v > u) {
                    conflict = 1;
                    break;
                }
            }
            if (conflict) break;
        }
        
        if (conflict) {
            color[v] = -1;
            // Find new color using optimized strategy
            bool used_colors[MAX_COLORS] = {false};
            int min_color = MAX_COLORS;
            
            // First pass: find used colors and minimum color
            for (int i = 0; i < neighbors_count; i++) {
                int neighbor = neighbors[i];
                if (color[neighbor] != -1) {
                    used_colors[color[neighbor]] = true;
                    min_color = min(min_color, color[neighbor]);
                }
            }
            
            // Try to reuse colors from neighbors first
            if (min_color < MAX_COLORS) {
                for (int c = 0; c < min_color; c++) {
                    if (!used_colors[c]) {
                        color[v] = c;
                        return;
                    }
                }
            }
            
            // If no reuse possible, find first available color
            for (int c = 0; c < MAX_COLORS; c++) {
                if (!used_colors[c]) {
                    color[v] = c;
                    return;
                }
            }
        }
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
        cudaEvent_t start, stop;
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
        cudaEventRecord(start);
        int blocks = (num_vertices + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;
        
        // Initial coloring
        parallel_coloring_kernel<<<blocks, THREADS_PER_BLOCK>>>(d_color, d_row_ptr, d_col_idx, num_vertices);
        
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
    printf("Parallel Graph Coloring (CUDA with Bucket Sort):\n");
    parallel_graph_coloring(row_ptr, col_idx, num_vertices, num_edges);
    free(row_ptr);
    free(col_idx);
    return 0;
} 