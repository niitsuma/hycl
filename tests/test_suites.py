"""Run every .lisp suite and fail on any FAIL it reports.

Each suite is a Common Lisp file that prints `(pass NAME)` or `(FAIL NAME ...)`
per case; this wrapper turns that into pytest results so the whole set can be
run with one command.

A suite that needs something the machine does not have -- Maxima, Quicklisp, a
Python package -- is skipped, not failed, and says why.  SBCL itself is not
optional: without the expander there is nothing to test.
"""

import contextlib
import functools
import io
import os
import pathlib
import shutil

import pytest

import hyclb  # noqa: F401  -- registers the .lisp import hook
from hyclb.api import cl_load, new_module

HERE = pathlib.Path(__file__).parent
SUITES = sorted(HERE.glob("*.lisp"))


def _has_module(name):
    """Importable, not merely present.

    find_spec answers yes for a package whose own dependencies are missing,
    and the suite then fails where it should have skipped.
    """
    import importlib
    try:
        importlib.import_module(name)
        return True
    except Exception:
        return False


def _has_quicklisp():
    return (pathlib.Path(os.environ.get("QUICKLISP_HOME",
                                        pathlib.Path.home() / "quicklisp"))
            / "setup.lisp").exists()


@functools.cache
def _lol_loads():
    """let-over-lambda, loadable by this SBCL at all.

    Its dependency lisp-namespace does not compile on every SBCL (2.5.11
    with the 2026-01-01 dist: LISP-NAMESPACE::*NAMESPACE-TABLE* is unbound).
    When plain SBCL cannot load the library, that is an upstream property,
    not a hyclb failure, so the suite that uses it should skip.
    """
    if not _has_quicklisp():
        return False
    import subprocess
    setup = (pathlib.Path(os.environ.get("QUICKLISP_HOME",
                                         pathlib.Path.home() / "quicklisp"))
             / "setup.lisp")
    r = subprocess.run(
        ["sbcl", "--non-interactive", "--no-userinit",
         "--eval", f'(load "{setup}")',
         "--eval", '(ql:quickload "let-over-lambda" :silent t)'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    return r.returncode == 0


# What each suite needs beyond SBCL and hyclb itself.  A suite absent from
# this table runs unconditionally.
NEEDS = {
    "ql": [("Quicklisp", _has_quicklisp)],
    "libraries": [("Quicklisp", _has_quicklisp),
                  ("let-over-lambda under this SBCL", _lol_loads)],
    "structs": [("torch", lambda: _has_module("torch"))],
    "sweep": [("torch", lambda: _has_module("torch")),
              ("lightning", lambda: _has_module("lightning"))],
    "lightning_demo": [("torch", lambda: _has_module("torch")),
                       ("lightning", lambda: _has_module("lightning"))],
    "maxima": [("Maxima", lambda: shutil.which("maxima"))],
    "maxima-apps": [("Maxima", lambda: shutil.which("maxima")),
                    ("torch", lambda: _has_module("torch"))],
    "lagrangian": [("Maxima", lambda: shutil.which("maxima"))],
    "sequences": [("Maxima", lambda: shutil.which("maxima")),
                  ("numpy", lambda: _has_module("numpy"))],
    "lasso": [("numpy", lambda: _has_module("numpy"))],
    "defsum": [("Maxima", lambda: shutil.which("maxima")),
               ("numpy", lambda: _has_module("numpy"))],
    # which(1) cannot tell whether a server answers behind the CLI; probing
    # on every run would cost more than the suite, so a dead server fails
    # rather than skips
    "llm": [("ask-local", lambda: shutil.which("ask-local"))],
}


@pytest.mark.parametrize("suite", SUITES, ids=lambda p: p.stem)
def test_suite(suite):
    for what, have in NEEDS.get(suite.stem, []):
        if not have():
            pytest.skip(f"{what} not available")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        cl_load(str(suite), new_module(suite.stem))
    text = output.getvalue()
    failures = [line for line in text.splitlines() if "FAIL" in line]
    assert not failures, "\n".join(failures)
