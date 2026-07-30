"""Run every .lisp suite and fail on any FAIL it reports.

Each suite is a Common Lisp file that prints `(pass NAME)` or `(FAIL NAME ...)`
per case; this wrapper turns that into pytest results so the whole set can be
run with one command.

A suite that needs something the machine does not have -- Maxima, Quicklisp, a
Python package -- is skipped, not failed, and says why.  SBCL itself is not
optional: without the expander there is nothing to test.
"""

import contextlib
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
    import importlib.util
    return importlib.util.find_spec(name) is not None


def _has_quicklisp():
    return (pathlib.Path(os.environ.get("QUICKLISP_HOME",
                                        pathlib.Path.home() / "quicklisp"))
            / "setup.lisp").exists()


# What each suite needs beyond SBCL and hyclb itself.  A suite absent from
# this table runs unconditionally.
NEEDS = {
    "ql": [("Quicklisp", _has_quicklisp)],
    "libraries": [("Quicklisp", _has_quicklisp)],
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
