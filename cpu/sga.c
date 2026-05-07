#include <stdio.h>
#include <stdlib.h>
#include "pthread_barrier_compat.h"
#include <pthread.h>
#include <stdbool.h>
#include <iostream>
#include <string>
#include <limits.h>
#include <time.h>

#define MAX_THREADS 8
#define MAX_COLORS 256
#define NUM_RUNS 10

typedef struct {
    int id, start, end, *color, *row_ptr, *col_idx, num_vertices;
} ThreadData;

pthread_barrier_t barrier;

int find_available_color(int *neighbors, int num_neighbors, int *color) {
    bool used_colors[MAX_COLORS] = {false};
    for (int i = 0; i < num_neighbors; i++) {
        int neighbor = neighbors[i];
        if (color[neighbor] != -1) used_colors[color[neighbor]] = true;
    }
    for (int c = 0; c < MAX_COLORS; c++) if (!used_colors[c]) return c;
    return MAX_COLORS;
}

void *parallel_coloring(void *arg) {
    ThreadData *data = (ThreadData *)arg;
    int *color = data->color, *row_ptr = data->row_ptr, *col_idx = data->col_idx;
    for (int v = data->start; v < data->end; v++) {
        int neighbors_count = row_ptr[v + 1] - row_ptr[v];
        int *neighbors = &col_idx[row_ptr[v]];
        color[v] = find_available_color(neighbors, neighbors_count, color);
    }
    pthread_barrier_wait(&barrier);
    for (int v = data->start; v < data->end; v++) {
        int neighbors_count = row_ptr[v + 1] - row_ptr[v];
        int *neighbors = &col_idx[row_ptr[v]];
        for (int i = 0; i < neighbors_count; i++) {
            int u = neighbors[i];
            if (color[v] == color[u] && v > u) color[v] = -1;
        }
    }
    pthread_barrier_wait(&barrier);
    for (int v = data->start; v < data->end; v++) {
        if (color[v] == -1) {
            int neighbors_count = row_ptr[v + 1] - row_ptr[v];
            int *neighbors = &col_idx[row_ptr[v]];
            color[v] = find_available_color(neighbors, neighbors_count, color);
        }
    }
    return NULL;
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
    for (int r = 0; r < NUM_RUNS; r++) {
        for (int i = 0; i < num_vertices; i++) color[i] = -1;
        pthread_t threads[MAX_THREADS];
        ThreadData thread_data[MAX_THREADS];
        pthread_barrier_init(&barrier, NULL, MAX_THREADS);
        clock_t start_time = clock();
        int chunk_size = num_vertices / MAX_THREADS;
        for (int i = 0; i < MAX_THREADS; i++) {
            thread_data[i] = {i, i * chunk_size, (i == MAX_THREADS - 1) ? num_vertices : (i + 1) * chunk_size, color, row_ptr, col_idx, num_vertices};
            pthread_create(&threads[i], NULL, parallel_coloring, &thread_data[i]);
        }
        for (int i = 0; i < MAX_THREADS; i++) pthread_join(threads[i], NULL);
        pthread_barrier_destroy(&barrier);
        clock_t end_time = clock();
        total_time += ((double)(end_time - start_time)) / CLOCKS_PER_SEC;
    }
    double avg_time = total_time / NUM_RUNS;
    int unique_colors = count_unique_colors(color, num_vertices);
    printf("Total edges: %d\nTotal nodes: %d\nNo of colors used: %d\nAverage time in seconds: %.6f\nAverage throughput: %.6f nodes/sec\n", 
           num_edges, num_vertices, unique_colors, avg_time, num_vertices / avg_time);
    free(color);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <input_file.csr>\n", argv[0]);
        return 1;
    }
    const char *file_path = argv[1];
    int *row_ptr, *col_idx, num_vertices, num_edges;
    read_csr(file_path, &row_ptr, &col_idx, &num_vertices, &num_edges);
    printf("Parallel Graph Coloring:\n");
    parallel_graph_coloring(row_ptr, col_idx, num_vertices, num_edges);
    free(row_ptr);
    free(col_idx);
    return 0;
}
