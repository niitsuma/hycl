"""Bring an existing Python program into the Lisp, then optimise it there.

    python examples/from_python.py

The point is the last step. The Python source has no way to ask for machine
code; the Lisp it becomes does, and the request is one declaration.
"""

import pathlib
import tempfile
import time

from hyclb.api import cl_eval, new_module
from hyclb.frompy import translate_source

PYTHON = '''
def leibniz(n):
    acc = 0.0
    sign = 1.0
    i = 0
    while i < n:
        acc += sign / (2.0 * i + 1.0)
        sign = -sign
        i += 1
    return 4.0 * acc
'''

DECLARATION = ("  (declare (type integer n)\n"
               "           (optimize (speed 3) (safety 0) (float-accuracy 0)))\n")


def main():
    lisp, renamed = translate_source(PYTHON)
    print("--- the Lisp it becomes " + "-" * 40)
    print(lisp[lisp.index("(defun"):].rstrip())
    if renamed:
        print(";; renamed:", renamed)

    # the same source with one declaration inserted after the lambda list
    at = lisp.index("\n", lisp.index("(defun leibniz")) + 1
    declared = lisp[:at] + DECLARATION + lisp[at:]

    plain, fast = new_module("plain"), new_module("fast")
    cl_eval(lisp, plain)
    cl_eval(declared, fast)

    scope = {}
    exec(compile(PYTHON, "<python>", "exec"), scope)

    n = 2_000_000
    fast.leibniz(10)                                   # let Numba compile
    print("\n--- " + str(n) + " terms " + "-" * 44)
    for label, fn in (("original Python", scope["leibniz"]),
                      ("translated, as written", plain.leibniz),
                      ("translated, one declaration added", fast.leibniz)):
        best = float("inf")
        for _ in range(3):
            t0 = time.perf_counter()
            value = fn(n)
            best = min(best, time.perf_counter() - t0)
        print(f"  {label:35s} {best * 1000:9.1f} ms   pi = {value:.9f}")
    print("\n(timings depend on what else the machine is doing; the value must"
          "\n not depend on anything.)")


if __name__ == "__main__":
    main()
