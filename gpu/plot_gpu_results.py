"""PGC: plot per-dataset GPU runtime and color counts produced by
``run_gpu_benchmarks.sh`` (`results/results_gpu.csv`).

Usage:
    python plot_gpu_results.py [csv_path]
"""
from __future__ import annotations

import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ALGORITHMS = ["SGA", "BRIGHT", "ECL", "ECLCR", "ECLML"]
COLORS = {
    "SGA":   "tab:red",
    "BRIGHT":"purple",
    "ECL":   "tab:blue",
    "ECLCR": "tab:green",
    "ECLML": "tab:orange",
}


def _bar(ax, df, value_col_template, ylabel, title):
    width = 0.15
    x = np.arange(len(df["Dataset"])) * 1.4
    offsets = np.linspace(-(len(ALGORITHMS) - 1) / 2, (len(ALGORITHMS) - 1) / 2, len(ALGORITHMS)) * width
    for offset, algo in zip(offsets, ALGORITHMS):
        col = value_col_template.format(algo=algo)
        ax.bar(x + offset, df[col].astype(float), width, label=algo, color=COLORS[algo])
    ax.set_xlabel("Dataset")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.set_xticks(x)
    ax.set_xticklabels(df["Dataset"], rotation=45, ha="right")
    ax.legend()


def main() -> None:
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("results/results_gpu.csv")
    if not csv_path.exists():
        sys.exit(f"CSV not found: {csv_path}")

    out_dir = csv_path.parent
    df = pd.read_csv(csv_path).replace("NA", np.nan).dropna()

    fig, ax = plt.subplots(figsize=(14, 7))
    _bar(ax, df, "{algo} Time (s)", "Execution Time (s)", "GPU Runtime per Algorithm")
    fig.tight_layout()
    fig.savefig(out_dir / "gpu_time.png", dpi=150)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(14, 7))
    _bar(ax, df, "{algo} Colors", "Number of Colors", "GPU Color Count per Algorithm")
    fig.tight_layout()
    fig.savefig(out_dir / "gpu_colors.png", dpi=150)
    plt.close(fig)

    print(f"Wrote {out_dir/'gpu_time.png'} and {out_dir/'gpu_colors.png'}")


if __name__ == "__main__":
    main()
