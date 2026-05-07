"""PGC: plot per-dataset CPU runtime and color counts produced by
``run_cpu_benchmarks.sh`` (`results/results_cpu.csv`).

Usage:
    python plot_cpu_results.py [csv_path]
"""
from __future__ import annotations

import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ALGORITHMS = ["SGA", "BRIGHT", "ECL", "ECLML"]
COLORS = {
    "SGA":   "#1f77b4",
    "BRIGHT":"#d62728",
    "ECL":   "#2ca02c",
    "ECLML": "#ff7f0e",
}


def _bar(ax, df, value_col_template, ylabel, title, fname):
    bar_width = 0.2
    index = np.arange(len(df["Dataset"]))
    for i, algo in enumerate(ALGORITHMS):
        col = value_col_template.format(algo=algo)
        ax.bar(
            index + i * bar_width,
            df[col].astype(float),
            bar_width,
            label=algo,
            color=COLORS[algo],
        )
    ax.set_xlabel("Dataset")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.set_xticks(index + 1.5 * bar_width)
    ax.set_xticklabels(df["Dataset"], rotation=45, ha="right")
    ax.legend()


def main() -> None:
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("results/results_cpu.csv")
    if not csv_path.exists():
        sys.exit(f"CSV not found: {csv_path}")

    out_dir = csv_path.parent
    df = pd.read_csv(csv_path).replace("NA", np.nan).dropna()

    fig, ax = plt.subplots(figsize=(12, 6))
    _bar(ax, df, "{algo} Time (s)", "Average Time (s)",
         "CPU Runtime per Algorithm", out_dir / "cpu_time.png")
    fig.tight_layout()
    fig.savefig(out_dir / "cpu_time.png", dpi=150)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(12, 6))
    _bar(ax, df, "{algo} Colors", "Number of Colors",
         "CPU Color Count per Algorithm", out_dir / "cpu_colors.png")
    fig.tight_layout()
    fig.savefig(out_dir / "cpu_colors.png", dpi=150)
    plt.close(fig)

    print(f"Wrote {out_dir/'cpu_time.png'} and {out_dir/'cpu_colors.png'}")


if __name__ == "__main__":
    main()
