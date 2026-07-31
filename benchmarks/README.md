# Benchmarks

Absolute times on this machine mean nothing unless it is quiet: the same code
has measured 632 ms and 1,135 ms in one afternoon. Everything here therefore
waits for the machine before measuring, watches the load while measuring, and
says so if it rose.

| | what it measures |
| --- | --- |
| `lasso.py` | LASSO coordinate descent: two hyclb compilations against NumPy, scikit-learn and cuML, over four problem sizes |
| `lasso_cuda.py` | the same on the GPU: a kernel launched per coordinate against one that keeps the sweep loop on the device |
| `paper_figures.py` | the smaller claims — the two compilations on a numeric loop, a lazy stream against the compiled kernel, build time against run time |
| `run_when_idle.sh` | waits for load below 4 and GPU below 10% for three consecutive minutes, then runs all three |
| `tfs_when_idle.sh` | the same for the temporal-feature-selection comparison against Scm2Cpp |

```console
$ benchmarks/run_when_idle.sh results/lasso-idle.txt        # up to 24h of waiting
$ benchmarks/tfs_when_idle.sh results/tfs-idle.txt LOADER.py
```

`results/` is not tracked; it is machine-specific output.

## What is settled and what is not

`results/lasso-idle.txt` and `results/tfs-idle.txt` were taken on a quiet
machine and are what the paper quotes. The three figures in `paper_figures.py`
are not yet: every attempt so far has been contended, and
`results/figures-CONTENDED-do-not-quote.txt` is kept as an example of what
that looks like — the load rose from 4.94 to 23.45 mid-run and two figures
for the same computation came out 2.7x apart. The paper marks those three in
place rather than presenting them as measured.
