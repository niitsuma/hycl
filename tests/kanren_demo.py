"""Compile si-kanren -- a Quicklisp library with a real runtime -- to Python.

Unlike the macro-only libraries, miniKanren is mostly ordinary functions:
substitutions, unification, streams.  They cannot expand away, so the library
itself is compiled through the system.  Nothing Lisp remains at run time.
"""

import os
import sys

from hyclb.api import cl_eval, new_module, set_readtable_case, _lisp


def source_directory(system):
    """Where Quicklisp put a system, according to Quicklisp.

    Asking is the only portable way: the version is in the directory name and
    the dist root moves with QUICKLISP_HOME.  The expander has already loaded
    the system, so ASDF there knows.
    """
    path = _lisp().eval(f'(namestring (asdf:system-source-directory "{system}"))')
    return str(path).strip('"')


QUERIES = [
    ("(run* (q) (== q 5))", "(si-kanren:run* (q) (si-kanren:== q 5))"),
    (
        "(run* (q) (fresh (x y) (== q (list x y)) (== x 1) (== y 2)))",
        "(si-kanren:run* (q) (si-kanren:fresh (x y)"
        " (si-kanren:== q (list x y)) (si-kanren:== x 1) (si-kanren:== y 2)))",
    ),
    (
        "(run 2 (q) (conde ((== q 1)) ((== q 2)) ((== q 3))))",
        "(si-kanren:run 2 (q) (si-kanren:conde ((si-kanren:== q 1))"
        " ((si-kanren:== q 2)) ((si-kanren:== q 3))))",
    ),
    (
        "(run* (q) (fresh (x) (== x 'cat) (== q (list x x))))",
        "(si-kanren:run* (q) (si-kanren:fresh (x) (si-kanren:== x (quote cat))"
        " (si-kanren:== q (list x x))))",
    ),
]


def main():
    mod = new_module("kanren")
    # the expander needs the macros; Python needs the functions
    cl_eval('(ql:quickload "si-kanren")', mod)
    src = os.path.join(source_directory("si-kanren"), "src")
    # an existing library is written in standard Common Lisp, which is
    # case-insensitive: C-of and c-of are one symbol
    set_readtable_case("upcase")
    for name in ("si-kanren", "wrappers"):
        with open(os.path.join(src, f"{name}.lisp")) as f:
            cl_eval(f.read(), mod)
    print("si-kanren compiled to Python")

    failures = 0
    for label, query in QUERIES:
        print(f"  {label}")
        print("    -> ", end="")
        try:
            cl_eval(query, mod)
            print()
        except Exception as exc:  # noqa: BLE001
            print("ERROR", type(exc).__name__, exc)
            failures += 1
    return failures


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
