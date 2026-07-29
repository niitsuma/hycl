"""LASSO by coordinate descent: what the (optimize (speed 3)) declaration buys.

The same algorithm is run six ways.  The first three come out of one Common
Lisp source file (tests/lasso.lisp); the last two are the established libraries
a practitioner would otherwise reach for.

  1. ordinary compilation      CL values on Python, our runtime
  2. (optimize (speed 3))      the same source, compiled through Numba
  3. + (float-accuracy 0)      and permitting the reductions to be vectorised
  4. NumPy                     the vectorised inner loop a Python author writes
  5. scikit-learn              Cython coordinate descent, CPU
  6. cuML                      GPU coordinate descent

The design matrix is laid out once, outside the timing; what each timed call
allocates is only the O(n+p) mutable state.  Every arm performs exactly SWEEPS full passes over the coordinates -- the
library solvers are given tol=0 so they cannot stop early -- and every arm's
answer is checked against the others.  Timings are the best of several runs;
run this on an otherwise idle machine, since arms 1-4 are single-threaded and
contend with anything else on the CPU.

    python benchmarks/lasso.py
"""

import argparse
import os
import pathlib
import sys
import time

# Our generated code is single-threaded, so hold the CPU arms to one thread
# each and compare like with like.  Must precede the NumPy import.
for _v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
           "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from hyclb.api import cl_load, new_module  # noqa: E402

LAM = 0.01
SWEEPS = 20
SIZES = [(500, 50), (2000, 200), (10000, 500), (200000, 200)]


def problem(n, p, seed=0):
    rng = np.random.default_rng(seed)
    X = rng.standard_normal((n, p))
    true = np.zeros(p)
    true[:5] = [3.0, -2.0, 1.5, 0.0, 4.0]
    return X, X @ true + 0.1 * rng.standard_normal(n)


def prepare(X, y):
    """The layout each arm reads, built once so it is not inside the timing.

    Coordinate descent sweeps one column at a time, so the design matrix is
    laid out column major; the Lisp code sees it flat and indexes j*n+i.
    """
    Xf = np.asfortranarray(X)
    return Xf, Xf.ravel(order="F").copy(), (X ** 2).sum(axis=0)


def state(y, p):
    """The mutable part: beta starts at zero, so the residual starts at y."""
    return np.zeros(p), y.copy()


def numpy_lasso(X, y, xnorm, lam, sweeps):
    n, p = X.shape
    beta, resid = state(y, p)
    g = lam * n
    for _ in range(sweeps):
        for j in range(p):
            old = beta[j]
            rho = X[:, j] @ resid + old * xnorm[j]
            new = (rho - g if rho > g else (rho + g if rho < -g else 0.0)) / xnorm[j]
            beta[j] = new
            resid -= X[:, j] * (new - old)
    return beta


def best(fn, reps):
    """Best of REPS, discarding the first run so JIT and warm-up do not count."""
    fn()
    t, out = float("inf"), None
    for _ in range(reps):
        t0 = time.perf_counter()
        out = fn()
        t = min(t, time.perf_counter() - t0)
    return t, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--no-gpu", action="store_true")
    ap.add_argument("--sizes", help="comma-separated NxP list, e.g. 500x50,2000x200")
    args = ap.parse_args()
    sizes = ([tuple(int(v) for v in s.split("x")) for s in args.sizes.split(",")]
             if args.sizes else SIZES)

    print(f"load average now: {', '.join(f'{x:.2f}' for x in os.getloadavg())}"
          f"   ({os.cpu_count()} cores; CPU arms pinned to one thread)")
    lasso = new_module("lasso_bench")
    cl_load(str(pathlib.Path(__file__).resolve().parent.parent / "tests" / "lasso.lisp"), lasso)

    sk = cuml_lasso = None
    try:
        from sklearn.linear_model import Lasso as sk
    except ImportError:
        print("scikit-learn not installed -- skipping that arm")
    if not args.no_gpu:
        try:
            from cuml.linear_model import Lasso as cuml_lasso
            import cupy
        except ImportError:
            print("cuML not installed -- skipping the GPU arm")

    for n, p in sizes:
        X, y = problem(n, p)
        Xf, xflat, xnorm = prepare(X, y)
        print(f"\n=== n={n}  p={p}  ({SWEEPS * p * 2 * n / 1e6:.0f}M inner iterations) ===")
        rows = []

        def run(fn):
            beta, resid = state(y, p)
            return np.asarray(fn(xflat, y, beta, resid, xnorm, LAM, SWEEPS, n, p))

        t, ref = best(lambda: run(lasso.lasso_fast), args.reps)
        rows.append(("hyclb, (optimize (speed 3))", t, ref))
        fast_time = t

        t, b = best(lambda: run(lasso.lasso_approx), args.reps)
        rows.append(("hyclb, + (float-accuracy 0)", t, b))

        t, b = best(lambda: numpy_lasso(Xf, y, xnorm, LAM, SWEEPS), max(1, args.reps // 2))
        rows.append(("NumPy, vectorised inner loop", t, b))

        if n <= 500:  # the unoptimised arm is far too slow to run at scale
            t0 = time.perf_counter()
            b = run(lasso.lasso_plain)
            rows.append(("hyclb, ordinary compilation", time.perf_counter() - t0, b))

        if sk is not None:
            t, m = best(lambda: sk(alpha=LAM, max_iter=SWEEPS, tol=0.0,
                                   fit_intercept=False).fit(X, y), args.reps)
            rows.append(("scikit-learn (Cython, CPU)", t, m.coef_))

        if cuml_lasso is not None:
            Xg, yg = cupy.asarray(X), cupy.asarray(y)

            def fit_gpu():
                m = cuml_lasso(alpha=LAM, max_iter=SWEEPS, tol=0.0,
                               fit_intercept=False).fit(Xg, yg)
                cupy.cuda.runtime.deviceSynchronize()
                return m
            t, m = best(fit_gpu, args.reps)
            rows.append(("cuML (GPU, data already on device)", t, cupy.asnumpy(m.coef_)))

            def fit_gpu_transfer():
                m = cuml_lasso(alpha=LAM, max_iter=SWEEPS, tol=0.0,
                               fit_intercept=False).fit(X, y)
                cupy.cuda.runtime.deviceSynchronize()
                return m
            t, _ = best(fit_gpu_transfer, args.reps)
            rows.append(("cuML (GPU, including host->device copy)", t, None))

        for label, t, b in sorted(rows, key=lambda r: r[1]):
            agree = "" if b is None else f"   max|diff| = {np.abs(b - ref).max():.1e}"
            print(f"  {label:39s} {t * 1000:9.1f} ms  {t / fast_time:8.2f}x{agree}")


if __name__ == "__main__":
    main()
