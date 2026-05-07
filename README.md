# PGC — Parallel Graph Coloring

Reference implementation and reproducibility package for **BRIGHT**
(*Bucket-based Recoloring and Iterative Greedy Heuristic Technique*),
a parallel graph-coloring algorithm targeting both multi-core CPUs
(via `pthread`) and NVIDIA GPUs (via CUDA), together with the baselines
used in the paper:

- **SGA** — Speculative Greedy Algorithm (baseline).
- **BRIGHT** — proposed bucket-prioritised speculative coloring with
  intelligent color reuse.
- **ECL / ECLCR / ECLML** — published parallel graph-coloring baselines
  used for comparison.

This repository contains the source, build/run drivers, and post-processing
scripts needed to reproduce the per-dataset runtime and color-count tables
in the paper.

## Repository layout

```
PGC/
├── README.md                 — this file
├── .gitignore
├── cpu/                      — multi-threaded (pthread) implementations
│   ├── sga.c                 — SGA baseline
│   ├── bright.cpp            — BRIGHT (proposed)
│   ├── ecl.cpp               — ECL baseline
│   ├── eclml.cpp             — ECLML baseline
│   ├── ECLgraph.h            — ECL graph (.egr) reader
│   ├── pthread_barrier_compat.h — macOS portability shim (no-op on Linux)
│   ├── run_cpu_benchmarks.sh — build + run + aggregate driver
│   ├── plot_cpu_results.py   — CSV → PNG plot script
│   └── results/              — reference results (paper run)
├── gpu/                      — CUDA implementations
│   ├── sga.cu                — SGA baseline
│   ├── bright.cu             — BRIGHT (proposed)
│   ├── ECL.cu                — ECL baseline
│   ├── ECLCR.cu              — ECLCR baseline
│   ├── ECLML.cu              — ECLML baseline
│   ├── ECLgraph.h
│   ├── run_gpu_benchmarks.sh — build + run + aggregate driver
│   ├── plot_gpu_results.py   — CSV → PNG plot script
│   └── results/              — reference results (paper run)
└── datasets/
    └── README.md             — where to obtain the 11 paper datasets
```

## Requirements

### CPU build
- A C++14 compiler with `pthread` support (GCC 9+ recommended).
- `bc` (used by the benchmark driver for floating-point averages).
- Python 3.9+ with `pandas`, `numpy`, and `matplotlib` for plotting.

### GPU build
- CUDA Toolkit 11.0+ (`nvcc`).
- An NVIDIA GPU; defaults target compute capability `sm_75`. Override via
  `NVCC_ARCH=sm_<your_arch> ./run_gpu_benchmarks.sh`.

## Datasets

Datasets are not redistributed in this repository. The benchmark drivers
read `.csr` files (for SGA / BRIGHT) and `.egr` files (for ECL / ECLCR / ECLML)
from `datasets/`. See [`datasets/README.md`](datasets/README.md) for the
canonical source URLs of each of the 11 graphs used in the paper and for
conversion instructions.

## Reproducing the paper

### 1. CPU runs

```bash
cd cpu
./run_cpu_benchmarks.sh
python plot_cpu_results.py
```

This writes:

- `cpu/results/results_cpu.csv`  — per-dataset averages over `PGC_RUNS` runs
  (default 10) for each algorithm.
- `cpu/results/cpu_time.png`     — runtime bar chart.
- `cpu/results/cpu_colors.png`   — color-count bar chart.

CSV columns:

```
Dataset, SGA Time (s), BRIGHT Time (s), ECL Time (s), ECLML Time (s),
SGA Colors, BRIGHT Colors, ECL Colors, ECLML Colors
```

### 2. GPU runs

```bash
cd gpu
./run_gpu_benchmarks.sh
python plot_gpu_results.py
```

This writes:

- `gpu/results/results_gpu.csv`  — per-dataset averages over `PGC_RUNS` runs
  for each algorithm.
- `gpu/results/gpu_time.png`     — runtime bar chart.
- `gpu/results/gpu_colors.png`   — color-count bar chart.

CSV columns:

```
Dataset, SGA Time (s), BRIGHT Time (s), ECL Time (s), ECLCR Time (s),
ECLML Time (s), SGA Colors, BRIGHT Colors, ECL Colors, ECLCR Colors,
ECLML Colors
```

### Tuning runs

Both drivers respect the following environment variables:

| Variable      | Default     | Effect                                    |
|---------------|-------------|-------------------------------------------|
| `PGC_RUNS`    | `10`        | Number of repetitions per (program, dataset). |
| `DATASET_DIR` | `../datasets` | Override the dataset search directory.   |
| `CXX`         | `g++`       | C++ compiler (CPU).                       |
| `CXXFLAGS`    | `-O3 -pthread` | C++ compile flags (CPU).               |
| `NVCC`        | `nvcc`      | CUDA compiler (GPU).                      |
| `NVCC_ARCH`   | `sm_75`     | Target GPU architecture (GPU).            |
| `NVCC_FLAGS`  | `-O3 -arch=$NVCC_ARCH` | Full nvcc flags (GPU).         |

## Reference results

`cpu/results/` and `gpu/results/` contain the CSVs and figures from the run
reported in the paper. They are kept under version control as a fixed
reference so that new runs (`results_cpu.csv`, `results_gpu.csv`) can be
diffed against them; the reference files are named
`results_cpu_reference.csv`, `results_reference.csv`,
`results_sga_reference.csv`.

## Reusing individual binaries

Each compiled binary takes a single input file:

```bash
./bright_cpu  /path/to/graph.csr
./ecl_cpu     /path/to/graph.egr   8     # second arg = thread count
./bright_gpu  /path/to/graph.csr
```

and prints a block ending with:

```
No of colors used: <k>
Average time in seconds: <t>
```

(or `colors used: <k>` and `avg runtime: <t>` for the ECL family).

## Citing

If you use this code or the BRIGHT algorithm in academic work, please cite
the accompanying paper.
