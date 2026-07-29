"""Can a hand-written CUDA kernel match cuML on this problem?

Coordinate descent is sweeps*p sequential steps, each one a length-n reduction
followed by a length-n update.  The steps are tiny, so what matters is not
arithmetic or bandwidth but how often the host has to be involved.  Issuing
kernels per coordinate from Python costs more than the whole computation --
measured at roughly half a millisecond per launch on a contended machine.

This version moves the entire sweep loop onto the device: one launch, with
grid-wide barriers between the three phases of each coordinate.  Compare with
benchmarks/lasso.py, which times the CPU compilations.

Requires a GPU that supports cooperative launches; the grid must be resident,
so the block count is held near the SM count.

    python benchmarks/lasso_cuda.py
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import os, time
for v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(v, "1")
import numpy as np
from numba import cuda, float64

TPB = 256


@cuda.jit
def cd_all(x, resid, beta, xnorm, lam_n, sweeps, n, p, partials, rho_out, nb):
    g = cuda.cg.this_grid()
    t = cuda.threadIdx.x
    b = cuda.blockIdx.x
    gid = b * cuda.blockDim.x + t
    stride = cuda.gridDim.x * cuda.blockDim.x
    buf = cuda.shared.array(TPB, float64)

    for _ in range(sweeps):
        for j in range(p):
            joff = j * n

            acc = 0.0                                   # phase 1: partial dots
            i = gid
            while i < n:
                acc += x[joff + i] * resid[i]
                i += stride
            buf[t] = acc
            cuda.syncthreads()
            s = cuda.blockDim.x // 2
            while s > 0:
                if t < s:
                    buf[t] += buf[t + s]
                cuda.syncthreads()
                s //= 2
            if t == 0:
                partials[b] = buf[0]
            g.sync()

            if gid == 0:                                # phase 2: finish the sum
                acc2 = 0.0
                for k in range(nb):
                    acc2 += partials[k]
                rho_out[0] = acc2
            g.sync()

            old = beta[j]                               # phase 3: update resid
            r = rho_out[0] + old * xnorm[j]
            if r > lam_n:
                sft = r - lam_n
            elif r < -lam_n:
                sft = r + lam_n
            else:
                sft = 0.0
            d = sft / xnorm[j] - old
            i = gid
            while i < n:
                resid[i] -= x[joff + i] * d
                i += stride
            g.sync()

            if gid == 0:                                # safe: all reads are past
                beta[j] = old + d


def problem(n, p, seed=0):
    rng = np.random.default_rng(seed)
    X = rng.standard_normal((n, p))
    true = np.zeros(p); true[:5] = [3.0, -2.0, 1.5, 0.0, 4.0]
    return X, X @ true + 0.1 * rng.standard_normal(n)


def best(fn, reps=5):
    fn()
    t, out = float("inf"), None
    for _ in range(reps):
        t0 = time.perf_counter(); out = fn(); t = min(t, time.perf_counter() - t0)
    return t, out


LAM, SWEEPS = 0.01, 20
dev = cuda.get_current_device()
# a cooperative launch needs the whole grid resident, so stay near the SM count
maxb = dev.MULTIPROCESSOR_COUNT * 2
print(f"GPU {dev.name.decode()}   {dev.MULTIPROCESSOR_COUNT} SMs; "
      f"using at most {maxb} blocks of {TPB}")

import cupy
from cuml.linear_model import Lasso
from hyclb.api import cl_load, new_module
HERE = pathlib.Path(__file__).resolve().parent.parent
lasso = new_module("lb"); cl_load(str(HERE / "tests" / "lasso.lisp"), lasso)

for n, p in [(2000, 200), (10000, 500), (200000, 200)]:
    X, y = problem(n, p)
    xflat = np.asfortranarray(X).ravel(order="F").copy()
    xnorm = (X ** 2).sum(axis=0)
    nb = min(maxb, max(1, (n + TPB - 1) // TPB))
    d_x, d_xn = cuda.to_device(xflat), cuda.to_device(xnorm)
    d_part, d_rho = cuda.device_array(nb), cuda.device_array(1)
    print(f"\n=== n={n} p={p}   ({nb} blocks, one launch, "
          f"{SWEEPS*p*3} grid barriers) ===")

    t, ref = best(lambda: lasso.lasso_approx(xflat, y, np.zeros(p), y.copy(),
                                             xnorm, LAM, SWEEPS, n, p))
    ref = np.asarray(ref)
    print(f"  CPU, hyclb + (float-accuracy 0)      {t*1000:9.1f} ms")

    def run_coop():
        d_beta = cuda.to_device(np.zeros(p))
        d_res = cuda.to_device(y.copy())
        cd_all[nb, TPB](d_x, d_res, d_beta, d_xn, LAM * n, SWEEPS, n, p,
                        d_part, d_rho, nb)
        cuda.synchronize()
        return d_beta.copy_to_host()
    t, b = best(run_coop)
    print(f"  cooperative CUDA kernel              {t*1000:9.1f} ms"
          f"   max|diff| = {np.abs(b-ref).max():.1e}")

    Xg, yg = cupy.asarray(X), cupy.asarray(y)
    def fit():
        m = Lasso(alpha=LAM, max_iter=SWEEPS, tol=0.0, fit_intercept=False).fit(Xg, yg)
        cupy.cuda.runtime.deviceSynchronize(); return m
    t, m = best(fit)
    print(f"  cuML                                 {t*1000:9.1f} ms"
          f"   max|diff| = {np.abs(cupy.asnumpy(m.coef_)-ref).max():.1e}")
