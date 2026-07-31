# Benchmarks

**[RESULTS.md](RESULTS.md) is the measured summary.** This file is about how
to reproduce it.

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

## What the paper quotes

All of it now comes from runs whose peak load stayed under the threshold:
`results/all-idle.txt` (peak 3.16) for the LASSO table, the CUDA arms and the
three smaller figures, and `results/tfs-idle.txt` for the Scm2Cpp
comparison. `results/figures-CONTENDED-do-not-quote.txt` is kept as an
example of what a bad run looks like — the load rose from 4.94 to 23.45
mid-run and two figures for the same computation came out 2.7x apart — which
is what the peak-load line now exists to catch.

One measurement had to be rewritten rather than merely repeated. The lazy
stream was being compared against a compiled loop summing i²+1, which LLVM
folds to a closed form: the compiled arm came out at 0.2 ns per term, meaning
it had been optimised away, and the ratio was measuring nothing. The term is
now a multiplicative hash reduced modulo a prime, which cannot be folded.
