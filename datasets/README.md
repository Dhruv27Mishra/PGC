# Datasets

The benchmark drivers expect graph files in this directory in two formats:

| Format | Used by                  | Extension |
|--------|--------------------------|-----------|
| CSR    | `sga`, `bright`          | `.csr`    |
| ECL    | `ecl`, `eclcr`, `eclml`  | `.egr`    |

The 11 datasets used in the paper are:

```
2d-2e20.sym, amazon0601, as-skitter, citationCiteseer, cit-Patents,
delaunay_n24, in-2004, internet, rmat22.sym, soc-LiveJournal1, USA-road-d.USA
```

## Where to obtain them

These graphs are widely used graph-coloring benchmarks. Sources include:

- **SNAP datasets** (`amazon0601`, `as-skitter`, `cit-Patents`, `soc-LiveJournal1`):
  <https://snap.stanford.edu/data/>
- **DIMACS Implementation Challenge** (`USA-road-d.USA`, `delaunay_n24`,
  `2d-2e20.sym`, `rmat22.sym`): <http://www.diag.uniroma1.it/challenge9/> and
  <https://www.cc.gatech.edu/dimacs10/>
- **LAW datasets** (`in-2004`): <https://law.di.unimi.it/datasets.php>
- **citationCiteseer** and **internet**: included with the
  ECL coloring distribution at <https://userweb.cs.txstate.edu/~burtscher/research/ECL-GC/>.

## Converting to CSR / ECL graph format

Use the converters bundled with the ECL graph-coloring distribution
(<https://userweb.cs.txstate.edu/~burtscher/research/ECL-GC/>) to produce
`.egr` files, and any standard CSR exporter (or the ECL utilities) for `.csr`
files. Both `sga` and `bright` read raw CSR triples
`(num_nodes, num_edges, row_ptr[], col_idx[])`; the layout matches that
emitted by the standard ECL toolchain.

Place the resulting files directly in this directory, e.g.:

```
PGC/datasets/amazon0601.csr
PGC/datasets/amazon0601.egr
```

You can override the dataset directory at run time:

```
DATASET_DIR=/path/to/your/datasets ./run_cpu_benchmarks.sh
```
