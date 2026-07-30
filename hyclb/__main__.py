"""Report whether this installation can do what it claims.

    python -m hyclb

Everything hyclb needs beyond the standard library is Hy and SBCL. The rest
buys specific features and is reported as present or absent, so an install
can be checked without reading the source to find out what it needs.
"""

import importlib
import shutil
import subprocess
import sys


def _module(name):
    try:
        m = importlib.import_module(name)
        return getattr(m, "__version__", "installed")
    except Exception:
        return None


def _sbcl():
    if not shutil.which("sbcl"):
        return None
    try:
        out = subprocess.run(["sbcl", "--version"], capture_output=True,
                             text=True, timeout=30)
        return out.stdout.strip() or "installed"
    except Exception:
        return None


def _quicklisp():
    import os
    import pathlib
    home = pathlib.Path(os.environ.get("QUICKLISP_HOME",
                                       pathlib.Path.home() / "quicklisp"))
    return str(home) if (home / "setup.lisp").exists() else None


def _maxima():
    return shutil.which("maxima")


def _round_trip():
    """The one check that matters: does a Lisp form become a Python value?"""
    from hyclb.api import cl_eval, new_module
    got = cl_eval("(defun sq (x) (* x x)) (sq 7)", new_module("selfcheck"))
    if got != 49:
        raise AssertionError(f"(sq 7) gave {got!r}, not 49")
    return "ok"


REQUIRED = [
    ("Python", lambda: ".".join(map(str, sys.version_info[:3])),
     "3.9 or later"),
    ("Hy", lambda: _module("hy"), "pip install hy"),
    ("SBCL", _sbcl, "apt install sbcl / brew install sbcl"),
]

OPTIONAL = [
    ("NumPy", lambda: _module("numpy"),
     "arrays; needed by most of the examples", "pip install numpy"),
    ("Numba", lambda: _module("numba"),
     "(optimize (speed 3)) becomes machine code", "pip install numba"),
    ("Maxima", _maxima,
     "computer algebra during compilation", "apt install maxima"),
    ("Quicklisp", _quicklisp,
     "Common Lisp libraries in the expander",
     "https://www.quicklisp.org/beta/#installation"),
    ("PyTorch", lambda: _module("torch"),
     "the Lightning and autograd examples", "pip install torch lightning"),
]


def main():
    width = 12
    print("hyclb installation check\n")
    ok = True
    print("required")
    for name, probe, hint in REQUIRED:
        got = probe()
        if got:
            print(f"  {name:<{width}} {got}")
        else:
            ok = False
            print(f"  {name:<{width}} MISSING -- {hint}")

    print("\noptional")
    for name, probe, what, hint in OPTIONAL:
        got = probe()
        if got:
            print(f"  {name:<{width}} {got}")
        else:
            print(f"  {name:<{width}} absent -- {what} ({hint})")

    if not ok:
        print("\nSomething required is missing; hyclb will not run.")
        return 1

    print("\ncompiling a Lisp function to Python ...", end=" ", flush=True)
    try:
        print(_round_trip())
    except Exception as e:
        print(f"FAILED\n  {type(e).__name__}: {e}")
        return 1
    print("\nThis installation works.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
