"""The remaining figures the paper quotes, measured in one place.

The LASSO table has its own harness (lasso.py, lasso_cuda.py). These are the
three smaller claims: what the two compilations cost on a numeric loop, what
a lazy stream costs per term against the compiled kernel, and where the time
goes between building a module and running it.

Run through benchmarks/run_when_idle.sh, or directly on a quiet machine:

    python benchmarks/paper_figures.py
"""

import functools
import os
import pathlib
import sys
import time

print = functools.partial(print, flush=True)   # so a long run shows progress

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from hyclb.api import cl_eval, new_module  # noqa: E402

LEIBNIZ = """
(defun leibniz-plain (n)
  (let ((acc 0.0) (sign 1.0) (i 0))
    (py-while (< i n)
      (setq acc (+ acc (/ sign (+ (* 2.0 i) 1.0))))
      (setq sign (- 0.0 sign))
      (setq i (+ i 1)))
    (* 4.0 acc)))

(defun leibniz-fast (n)
  (declare (type integer n) (optimize (speed 3) (safety 0)))
  (let ((acc 0.0) (sign 1.0) (i 0))
    (py-while (< i n)
      (setq acc (+ acc (/ sign (+ (* 2.0 i) 1.0))))
      (setq sign (- 0.0 sign))
      (setq i (+ i 1)))
    (* 4.0 acc)))
"""


def leibniz_python(n):
    acc, sign, i = 0.0, 1.0, 0
    while i < n:
        acc += sign / (2.0 * i + 1.0)
        sign = -sign
        i += 1
    return 4.0 * acc


def best(fn, reps=3):
    fn()
    t, out = float("inf"), None
    for _ in range(reps):
        t0 = time.perf_counter()
        out = fn()
        t = min(t, time.perf_counter() - t0)
    return t, out


def two_compilations():
    print("=== the two compilations, on 2e6 Leibniz terms ===")
    m = new_module("leibniz")
    cl_eval(LEIBNIZ, m)
    n = 2_000_000
    rows = []
    for label, fn in (("hyclb, ordinary compilation", m.leibniz_plain),
                      ("hyclb, (optimize (speed 3))", m.leibniz_fast),
                      ("hand-written Python", leibniz_python)):
        t, value = best(lambda fn=fn: fn(n))
        rows.append((label, t, value))
    base = [t for label, t, _ in rows if "Python" in label][0]
    for label, t, value in rows:
        ratio = base / t
        print(f"  {label:32s} {t * 1000:9.1f} ms   {ratio:8.1f}x   pi={value:.9f}")


STREAM = """
;; A term small enough to stay in a machine word: the point is the cost of
;; the stream cell against the cost of the arithmetic, and 2^n would make the
;; arithmetic bignum work that swamps both.
(defun term (n)
  (declare (type integer n) (optimize (speed 3) (safety 0)))
  (+ (* n n) 1))

(defun sum-compiled (n)
  (declare (type integer n) (optimize (speed 3) (safety 0)))
  (let ((acc 0) (i 0))
    (py-while (< i n) (setq acc (+ acc (+ (* i i) 1)))
              (setq i (+ i 1)))
    acc))

(defun mersenne-from (n) (cons-stream (term n) (mersenne-from (+ n 1))))

(defun sum-stream (n)
  (let ((s (mersenne-from 0)) (acc 0) (i 0))
    (py-while (< i n)
      (setq acc (+ acc (stream-car s)))
      (setq s (stream-cdr s))
      (setq i (+ i 1)))
    acc))
"""


def stream_versus_kernel():
    print("\n=== a term through the lazy stream, against the compiled loop ===")
    m = new_module("streams")
    try:
        cl_eval(STREAM, m)
    except Exception as e:
        print(f"  skipped: {type(e).__name__}: {str(e)[:70]}")
        return
    n = 2000
    tc, vc = best(lambda: m.sum_compiled(n))
    ts, vs = best(lambda: m.sum_stream(n))
    if vc != vs:
        print(f"  the two disagree ({vc} vs {vs}); not reporting a ratio")
        return
    print(f"  compiled loop                   {tc / n * 1e9:9.1f} ns per term")
    print(f"  lazy stream                     {ts / n * 1e9:9.1f} ns per term")
    print(f"  ratio                           {ts / tc:9.1f}x")


def build_versus_run():
    print("\n=== building a module against running it ===")
    src = """
(defun sum-to (n)
  (declare (type integer n) (optimize (speed 3) (safety 0)))
  (let ((acc 0) (i 0))
    (py-while (< i n) (setq acc (+ acc i)) (setq i (+ i 1)))
    acc))
"""
    from hyclb.api import expand, to_models
    import hy

    t0 = time.perf_counter()
    expand(src)
    t_expand = time.perf_counter() - t0

    models = to_models(src)
    t0 = time.perf_counter()
    m2 = new_module("buildrun2")
    for model in models:
        hy.eval(model, module=m2)
    t_compile = time.perf_counter() - t0

    t_run, value = best(lambda: m2.sum_to(1_000_000))
    print(f"  expand and translate (SBCL)     {t_expand * 1000:9.1f} ms")
    print(f"  Hy compilation and definition   {t_compile * 1000:9.1f} ms")
    print(f"  execution, 1e6 iterations       {t_run * 1000:9.1f} ms   "
          f"(= {value})")


def main():
    print(f"load average now: "
          f"{', '.join(f'{x:.2f}' for x in os.getloadavg())}   "
          f"({os.cpu_count()} cores)\n")
    two_compilations()
    stream_versus_kernel()
    build_versus_run()


if __name__ == "__main__":
    main()
