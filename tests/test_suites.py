"""Run every .lisp suite and fail on any FAIL it reports.

Each suite is a Common Lisp file that prints `(pass NAME)` or `(FAIL NAME ...)`
per case; this wrapper turns that into pytest results so the whole set can be
run with one command.
"""

import contextlib
import io
import pathlib

import pytest

import hyclb  # noqa: F401  -- registers the .lisp import hook
from hyclb.api import cl_load, new_module

HERE = pathlib.Path(__file__).parent
SUITES = sorted(HERE.glob("*.lisp"))


@pytest.mark.parametrize("suite", SUITES, ids=lambda p: p.stem)
def test_suite(suite):
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        cl_load(str(suite), new_module(suite.stem))
    text = output.getvalue()
    failures = [line for line in text.splitlines() if "FAIL" in line]
    assert not failures, "\n".join(failures)
