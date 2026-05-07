#!/usr/bin/env bash
# PGC: Parallel Graph Coloring (GPU benchmark driver)
# Builds and runs SGA, BRIGHT, ECL, ECLCR, and ECLML on every dataset under
# ../datasets/ and writes aggregate timings and color counts to
# results/results_gpu.csv.
#
# .csr inputs are expected for SGA/BRIGHT; .egr inputs for ECL/ECLCR/ECLML.
# See ../datasets/README.md for instructions.

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p results

NVCC="${NVCC:-nvcc}"
NVCC_ARCH="${NVCC_ARCH:-sm_75}"
NVCC_FLAGS="${NVCC_FLAGS:--O3 -arch=$NVCC_ARCH}"

echo -e "${BLUE}Compiling CUDA sources with $NVCC ($NVCC_FLAGS)${NC}"
$NVCC $NVCC_FLAGS sga.cu    -o sga_gpu    || { echo -e "${RED}Failed to compile sga.cu${NC}"; exit 1; }
$NVCC $NVCC_FLAGS bright.cu -o bright_gpu || { echo -e "${RED}Failed to compile bright.cu${NC}"; exit 1; }
$NVCC $NVCC_FLAGS ECL.cu    -o ecl_gpu    || { echo -e "${RED}Failed to compile ECL.cu${NC}"; exit 1; }
$NVCC $NVCC_FLAGS ECLCR.cu  -o eclcr_gpu  || { echo -e "${RED}Failed to compile ECLCR.cu${NC}"; exit 1; }
$NVCC $NVCC_FLAGS ECLML.cu  -o eclml_gpu  || { echo -e "${RED}Failed to compile ECLML.cu${NC}"; exit 1; }

OUT_CSV="results/results_gpu.csv"
echo "Dataset,SGA Time (s),BRIGHT Time (s),ECL Time (s),ECLCR Time (s),ECLML Time (s),SGA Colors,BRIGHT Colors,ECL Colors,ECLCR Colors,ECLML Colors" > "$OUT_CSV"

run_avg() {
    local program="$1" dataset="$2" extra_args="${3:-}"
    local total_time=0 total_colors=0 runs=0
    local n_runs="${PGC_RUNS:-10}"

    for ((i=1; i<=n_runs; i++)); do
        if [ ! -f "$dataset" ]; then
            echo "NA NA"
            return 1
        fi
        local output
        output=$(./"$program" "$dataset" $extra_args 2>&1) || { echo "NA NA"; return 1; }

        local execution_time colors
        if [[ "$program" == "ecl_gpu" || "$program" == "eclml_gpu" || "$program" == "eclcr_gpu" ]]; then
            execution_time=$(echo "$output" | grep "avg runtime:" | awk '{print $3}')
            colors=$(echo "$output"          | grep "colors used:" | awk '{print $3}')
        else
            execution_time=$(echo "$output" | grep "Average time in seconds:" | awk '{print $5}')
            colors=$(echo "$output"          | grep "No of colors used:"      | awk '{print $5}')
        fi

        [ -z "$execution_time" ] && continue
        [ -z "$colors" ] && continue

        total_time=$(echo "$total_time + $execution_time" | bc -l)
        total_colors=$(echo "$total_colors + $colors"     | bc -l)
        runs=$((runs + 1))
    done

    [ "$runs" -eq 0 ] && { echo "NA NA"; return 1; }
    local avg_time avg_colors
    avg_time=$(echo   "scale=6; $total_time   / $runs" | bc -l)
    avg_colors=$(echo "scale=2; $total_colors / $runs" | bc -l)
    echo "$avg_time $avg_colors"
}

DATASET_DIR="${DATASET_DIR:-../datasets}"
echo -e "${BLUE}Scanning datasets under $DATASET_DIR${NC}"

shopt -s nullglob
egr_files=("$DATASET_DIR"/*.egr)
[ "${#egr_files[@]}" -eq 0 ] && { echo -e "${YELLOW}No .egr datasets found in $DATASET_DIR${NC}"; exit 0; }

for dataset in "${egr_files[@]}"; do
    name=$(basename "$dataset")
    base="${name%.*}"
    csr_file="$DATASET_DIR/${base}.csr"

    echo -e "${BLUE}Processing $name${NC}"

    if [ -f "$csr_file" ]; then
        read sga_time     sga_colors    < <(run_avg sga_gpu     "$csr_file")
        read bright_time  bright_colors < <(run_avg bright_gpu  "$csr_file")
    else
        sga_time="NA"; sga_colors="NA"; bright_time="NA"; bright_colors="NA"
        echo -e "${YELLOW}  Skipping SGA/BRIGHT for $name (.csr not found)${NC}"
    fi
    read ecl_time    ecl_colors   < <(run_avg ecl_gpu   "$dataset" 8)
    read eclcr_time  eclcr_colors < <(run_avg eclcr_gpu "$dataset" 8)
    read eclml_time  eclml_colors < <(run_avg eclml_gpu "$dataset" 8)

    echo "$name,$sga_time,$bright_time,$ecl_time,$eclcr_time,$eclml_time,$sga_colors,$bright_colors,$ecl_colors,$eclcr_colors,$eclml_colors" >> "$OUT_CSV"
    echo -e "  ${GREEN}SGA${NC}     ${sga_time}s, ${sga_colors} colors"
    echo -e "  ${GREEN}BRIGHT${NC}  ${bright_time}s, ${bright_colors} colors"
    echo -e "  ${GREEN}ECL${NC}     ${ecl_time}s, ${ecl_colors} colors"
    echo -e "  ${GREEN}ECLCR${NC}   ${eclcr_time}s, ${eclcr_colors} colors"
    echo -e "  ${GREEN}ECLML${NC}   ${eclml_time}s, ${eclml_colors} colors"
done

echo -e "${GREEN}Done. Results written to $OUT_CSV${NC}"
