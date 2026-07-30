"""Compile and run Common Lisp source on Python.

SBCL reads and macroexpands; this module translates what comes back and hands
it to Hy's compiler.  SBCL takes no part in running the result.
"""

import bisect
import types

import hy
from hy import models as M

from . import sbcl, translate
from .translate import ref, sym
from .runtime import NIL, Cons, Keyword, Symbol

# Operators we translate ourselves, so macroexpansion stops before they turn
# into implementation-internal code.  Raising the frontier here trades
# compatibility for more readable output; see cl.hy.
STOP = [
    "defun",
    "lambda",
    "block",
    "return-from",
    "tagbody",
    "go",
    "unwind-protect",
    "multiple-value-bind",
    # these expand into implementation-internal arithmetic, so we stop short
    # of them and translate them ourselves
    "incf",
    "decf",
    "push",
    "pop",
    "destructuring-bind",
    "defstruct",
    "py-with",
    "py-global",
    "py-while",
    "py-for",
    "py-nonlocal",
    "py-import",
    "py-import-as",
    "defclass",
    "defmethod",
    "defgeneric",
    "make-instance",
    "defvar",
    "defparameter",
    "handler-case",
    "handler-bind",
    "restart-case",
    "define-condition",
    "defun-async",
    "defun-decorated",
]

PRELUDE = [
    M.Expression([sym("import"), ref("hyclb.runtime"), sym("*")]),
    M.Expression([sym("require"), ref("hyclb.cl"), sym("*")]),
]


def _lisp():
    lisp = sbcl.shared()
    if not getattr(lisp, "_stop_set", False):
        lisp.set_stop(STOP)
        lisp._stop_set = True
    return lisp


def _escape(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def set_readtable_case(mode):
    """Choose how the reader folds case.

    "invert" (the default) lets a Common Lisp symbol spell a Python
    identifier exactly.  "upcase" is standard Common Lisp, and is what an
    existing library needs: such code freely writes `C-of` and `c-of` for the
    same symbol, which :invert would keep apart.
    """
    _lisp().set_case(mode)


def expand(source, with_lines=False):
    """Read and macroexpand every top-level form in SOURCE.

    Returns the forms that still need translating; macro definitions and the
    like stay behind in the expander.  With WITH_LINES, each form is paired
    with the line of SOURCE it came from.
    """
    lisp = _lisp()
    result = lisp._request(":expand-string " + _escape(source))
    out = []
    starts = None
    for entry in _iter(result):
        tag = entry.car
        if isinstance(tag, Keyword) and tag.name.lower() == "skip":
            continue
        form = entry.cdr.car
        if not with_lines:
            out.append(form)
            continue
        if starts is None:                      # offset -> line, built once
            starts = [0]
            for i, ch in enumerate(source):
                if ch == "\n":
                    starts.append(i + 1)
        offset = entry.cdr.cdr.car if isinstance(entry.cdr.cdr, Cons) else None
        line = bisect.bisect_right(starts, offset) if isinstance(offset, int) else 1
        out.append((form, max(1, line)))
    return out


def _stamp(model, line):
    """Give a translated model the line of the .lisp form it came from.

    Hy turns these into Python line numbers, so a runtime traceback names the
    Lisp source rather than the generated code.  Only whole top-level forms
    are located: what SBCL hands back has been through macroexpansion and no
    longer corresponds to the source expression by expression.
    """
    if not isinstance(model, hy.models.Object):
        return model
    model.start_line = model.end_line = line
    model.start_column = model.end_column = 1
    if isinstance(model, hy.models.Sequence):
        for child in model:
            _stamp(child, line)
    return model


def to_models(source):
    return [_stamp(translate.translate(f), line)
            for f, line in expand(source, with_lines=True)]


def new_module(name="__cl__"):
    mod = types.ModuleType(name)
    mod.__dict__["__name__"] = name
    for form in PRELUDE:
        hy.eval(form, module=mod)
    return mod


def cl_eval(source, module=None):
    """Run SOURCE, returning the value of its last form."""
    mod = module if module is not None else new_module()
    value = NIL
    for model in to_models(source):
        value = hy.eval(model, module=mod)
    return value


def cl_load(path, module=None):
    with open(path) as f:
        return cl_eval(f.read(), module)


def _iter(x):
    while isinstance(x, Cons):
        yield x.car
        x = x.cdr
