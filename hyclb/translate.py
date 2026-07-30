"""Translate expanded Common Lisp forms into Hy models.

After SBCL is done, what is left is the 25 CL special operators plus function
calls, so this layer is small and closed.  Special operators are renamed to
private ``cl-*`` names implemented as macros in cl.hy; nothing here relies on
shadowing Hy's own forms.
"""

from fractions import Fraction

from hy import models as M

from .runtime import CL_TYPE_MAP, NIL, T, Cons, Keyword, Symbol

# CL special operators (and a few macros we stop expansion at) mapped to the
# macros in cl.hy.  PROGN is Hy's `do` unchanged.
SPECIAL = {
    "if": "cl-if",
    "let": "cl-let",
    "let*": "cl-let-star",
    "progn": "do",
    "locally": "do",
    "setq": "cl-setq",
    "block": "cl-block",
    "return-from": "cl-return-from",
    "tagbody": "cl-tagbody",
    "go": "cl-go",
    "function": "cl-function",
    "lambda": "cl-lambda",
    "defun": "cl-defun",
    "%tail-recur": "cl-tail-recur",
    "%tail-return": "cl-tail-return",
    "flet": "cl-flet",
    "labels": "cl-labels",
    "unwind-protect": "cl-unwind-protect",
    "declare": "cl-declare",
    "multiple-value-bind": "cl-multiple-value-bind",
    "incf": "cl-incf",
    "decf": "cl-decf",
    "push": "cl-push",
    "pop": "cl-pop",
    "py-import": "cl-py-import",
    "py-import-as": "cl-py-import-as",
    "destructuring-bind": "cl-destructuring-bind",
    "py-with": "cl-py-with",
    "defstruct": "cl-defstruct",
    "defclass": "cl-defclass",
    "defmethod": "cl-defmethod",
    "defgeneric": "cl-defgeneric",
    "defvar": "cl-defvar",
    "defparameter": "cl-defparameter",
    "py-del": "cl-py-del",
    "py-reraise": "cl-py-reraise",
    "py-locals": "cl-py-locals",
    "py-import-star": "cl-py-import-star",
    "py-while": "cl-py-while",
    "py-for": "cl-py-for",
    "py-break": "cl-py-break",
    "py-continue": "cl-py-continue",
    "py-and": "cl-py-and",
    "py-or": "cl-py-or",
    "py-global": "cl-py-global",
    "py-nonlocal": "cl-py-nonlocal",
    "py-yield": "cl-py-yield",
    "py-yield-from": "cl-py-yield-from",
    "py-await": "cl-py-await",
    "defun-async": "cl-defun-async",
    "defun-decorated": "cl-defun-decorated",
    "declaim": "cl-declare",
    "dotimes": "cl-dotimes",
    "cons-stream": "cl-cons-stream",
    "dolist": "cl-dolist",
    "handler-case": "cl-handler-case",
    "handler-bind": "cl-handler-bind",
    "restart-case": "cl-restart-case",
    "define-condition": "cl-define-condition",
}

# CL functions provided by runtime.py.
RUNTIME = {
    "car": "cl-car",
    "cdr": "cl-cdr",
    "cons": "cl-cons",
    "list": "cl-list",
    "list*": "cl-list-star",
    "null": "cl-null",
    "not": "cl-not",
    "consp": "cl-consp",
    "atom": "cl-atom",
    "listp": "cl-listp",
    "symbolp": "cl-symbolp",
    "eq": "cl-eq",
    "eql": "cl-eql",
    "equal": "cl-equal",
    "rplaca": "cl-rplaca",
    "rplacd": "cl-rplacd",
    "length": "cl-length",
    "append": "cl-append",
    "reverse": "cl-reverse",
    "nth": "cl-nth",
    "elt": "cl-elt",
    "funcall": "cl-funcall",
    "apply": "cl-apply",
    "values": "cl-values",
    "print": "cl-print",
    "error": "cl-error",
    "/": "cl-div",
    "1+": "cl-1plus",
    "1-": "cl-1minus",
    "=": "cl-numeq",
    "/=": "cl-numne",
    "<": "cl-lt",
    ">": "cl-gt",
    "<=": "cl-le",
    ">=": "cl-ge",
    "endp": "cl-endp",
    "mod": "cl-mod",
    "rem": "cl-rem",
    "zerop": "cl-zerop",
    "plusp": "cl-plusp",
    "minusp": "cl-minusp",
    "oddp": "cl-oddp",
    "evenp": "cl-evenp",
    "numberp": "cl-numberp",
    "stringp": "cl-stringp",
    "functionp": "cl-functionp",
    "mapcar": "cl-mapcar",
    "mapc": "cl-mapc",
    "member": "cl-member",
    "assoc": "cl-assoc",
    "remove": "cl-remove",
    "first": "cl-first",
    "second": "cl-second",
    "third": "cl-third",
    "cadr": "cl-cadr",
    "caar": "cl-caar",
    "cddr": "cl-cddr",
    "caddr": "cl-caddr",
    "last": "cl-last",
    "butlast": "cl-butlast",
    "nthcdr": "cl-nthcdr",
    "gensym": "cl-gensym",
    "string=": "cl-string-eq",
    "py-call": "cl-py-call",
    "py-attr": "cl-py-attr",
    "py-set-attr": "cl-py-set-attr",
    "py-method": "cl-py-method",
    "py-getitem": "cl-py-getitem",
    "py-setitem": "cl-py-setitem",
    "py-list": "cl-py-list",
    "py-tuple": "cl-py-tuple",
    "to-py": "to-py",
    "from-py": "from-py",
    "py-class": "cl-py-class",
    "py-class-body": "cl-py-class-body",
    "py-call-ex": "cl-py-call-ex",
    "py-raise": "cl-py-raise",
    "py-binop": "cl-py-binop",
    "py-unop": "cl-py-unop",
    "py-truthy": "cl-py-truthy",
    "py-dict": "cl-py-dict",
    "py-set": "cl-py-set",
    "py-slice": "cl-py-slice",
    "py-true": "py-true",
    "py-false": "py-false",
    "py-none": "py-none",
    "identity": "cl-identity",
    "abs": "cl-abs",
    "min": "cl-min",
    "max": "cl-max",
    "expt": "cl-expt",
    "sqrt": "cl-sqrt",
    "floor": "cl-floor",
    "ceiling": "cl-ceiling",
    "truncate": "cl-truncate",
    "round": "cl-round",
    "subseq": "cl-subseq",
    "concatenate": "cl-concatenate",
    "find": "cl-find",
    "position": "cl-position",
    "count": "cl-count",
    "find-if": "cl-find-if",
    "position-if": "cl-position-if",
    "count-if": "cl-count-if",
    "remove-if": "cl-remove-if",
    "remove-if-not": "cl-remove-if-not",
    "every": "cl-every",
    "some": "cl-some",
    "notany": "cl-notany",
    "reduce": "cl-reduce",
    "sort": "cl-sort",
    "copy-list": "cl-copy-list",
    "nreverse": "cl-nreverse",
    "nconc": "cl-nconc",
    "mapcan": "cl-mapcan",
    "getf": "cl-getf",
    "make-hash-table": "cl-make-hash-table",
    "gethash": "cl-gethash",
    "remhash": "cl-remhash",
    "hash-table-count": "cl-hash-table-count",
    "format": "cl-format",
    "princ": "cl-princ",
    "terpri": "cl-terpri",
    "symbol-name": "cl-symbol-name",
    "string": "cl-string",
    "string-upcase": "cl-string-upcase",
    "string-downcase": "cl-string-downcase",
    "char=": "cl-char-eq",
    "%puthash": "cl-puthash",
    "struct-class": "cl-struct-class",
    "make-struct": "cl-make-struct",
    "struct-p": "cl-struct-p",
    "slot": "cl-slot",
    "set-slot": "cl-set-slot",
    "copy-struct": "cl-copy-struct",
    "generic": "cl-generic",
    "add-method": "cl-add-method",
    "call-next-method": "cl-call-next-method",
    "next-method-p": "cl-next-method-p",
    "make-instance": "cl-make-instance",
    "slot-value": "cl-slot-value",
    "set-slot-value": "cl-set-slot-value",
    "find-class": "cl-find-class",
    "register-class": "cl-register-class",
    "condition-class": "cl-condition-class",
    "define-condition": "cl-define-condition",
    "make-condition": "cl-make-condition",
    "signal": "cl-signal",
    "push-restarts": "cl-push-restarts",
    "pop-restarts": "cl-pop-restarts",
    "invoke-restart": "cl-invoke-restart",
    "find-restart": "cl-find-restart",
    "sin": "cl-sin",
    "cos": "cl-cos",
    "tan": "cl-tan",
    "exp": "cl-exp",
    "log": "cl-log",
    "py-staticmethod": "py-staticmethod",
    "cdar": "cl-cdar",
    "caaar": "cl-caaar",
    "caadr": "cl-caadr",
    "cadar": "cl-cadar",
    "cdaar": "cl-cdaar",
    "cdadr": "cl-cdadr",
    "cddar": "cl-cddar",
    "cdddr": "cl-cdddr",
    "caaaar": "cl-caaaar",
    "caaadr": "cl-caaadr",
    "caadar": "cl-caadar",
    "caaddr": "cl-caaddr",
    "cadaar": "cl-cadaar",
    "cadadr": "cl-cadadr",
    "caddar": "cl-caddar",
    "cadddr": "cl-cadddr",
    "cdaaar": "cl-cdaaar",
    "cdaadr": "cl-cdaadr",
    "cdadar": "cl-cdadar",
    "cdaddr": "cl-cdaddr",
    "cddaar": "cl-cddaar",
    "cddadr": "cl-cddadr",
    "cdddar": "cl-cdddar",
    "cddddr": "cl-cddddr",
    "vector": "cl-vector",
    "aref": "cl-aref",
    "svref": "cl-svref",
    "make-array": "cl-make-array",
    "vectorp": "cl-vectorp",
    "arrayp": "cl-arrayp",
    "simple-vector-p": "cl-simple-vector-p",
    "characterp": "cl-characterp",
    "integerp": "cl-integerp",
    "floatp": "cl-floatp",
    "keywordp": "cl-keywordp",
    "equalp": "cl-equalp",
    "notevery": "cl-notevery",
    "remove-duplicates": "cl-remove-duplicates",
    "set-difference": "cl-set-difference",
    "union": "cl-union",
    "intersection": "cl-intersection",
    "typep": "cl-typep",
    "map": "cl-map",
    "mapl": "cl-mapl",
    "stream-cons": "cl-stream-cons",
    "stream-car": "cl-stream-car",
    "stream-cdr": "cl-stream-cdr",
    "stream-take": "cl-stream-take",
    "stream-nth": "cl-stream-nth",
    "stream-map": "cl-stream-map",
    "%rplacd": "cl-setcdr",
    "%rplaca": "cl-setcar",
}

# CL operators whose Python meaning is close enough that Hy's own operator
# macros compile them directly, which keeps the generated code readable.
# Common Lisp already has a way to say what type something is, and SBCL
# already reads it.  DECLARE and the :type slot option therefore become Python
# annotations, rather than a syntax of our own invention.

RETURN_TYPES = {}


def _python_type(spec):
    """The Python annotation for a Common Lisp type specifier, if we know one."""
    head = spec.car if isinstance(spec, Cons) else spec
    if not isinstance(head, Symbol):
        return None
    got = CL_TYPE_MAP.get(head.name)
    return got.__name__ if got is not None else None


def _declared_types(body):
    """Collect (declare (type T v...)) and (declare (T v...)) from a body."""
    out = {}
    for form in body:
        if not (isinstance(form, Cons) and isinstance(form.car, Symbol)
                and form.car.name == "declare"):
            continue
        for spec in _iter(form.cdr):
            if not isinstance(spec, Cons) or not isinstance(spec.car, Symbol):
                continue
            if spec.car.name == "type":
                kind, names = spec.cdr.car, list(_iter(spec.cdr.cdr))
            else:
                kind, names = spec.car, list(_iter(spec.cdr))
            py = _python_type(kind)
            if py is None:
                continue
            for n in names:
                if isinstance(n, Symbol):
                    out[n.name] = py
    return out


def _annotate(model, py_type):
    return M.Expression([sym("annotate"), model, sym(py_type)])


def _annotate_params(params, types):
    out = []
    for p in params:
        name = str(p) if isinstance(p, M.Symbol) else None
        if name is not None and name in types:
            out.append(_annotate(p, types[name]))
        elif isinstance(p, M.List) and len(p) and isinstance(p[0], M.Symbol) \
                and str(p[0]) in types:
            out.append(M.List([_annotate(p[0], types[str(p[0])])] + list(p[1:])))
        else:
            out.append(p)
    return M.List(out)


OPERATORS = {"+", "-", "*"}
OPERATORS_RENAMED = {}


class TranslationError(Exception):
    pass


def sym(name):
    return M.Symbol(name)


def ref(name):
    """A reference to NAME.

    A Common Lisp symbol may be spelled `numpy.array`, which Hy represents not
    as a symbol but as the attribute-access form `(. numpy array)` -- Hy's
    compiler dispatches on the exact model type, so there is no way to smuggle
    a dotted symbol past it.
    """
    if "." in name and not name.startswith(".") and not name.endswith("."):
        return M.Expression([M.Symbol(".")] + [M.Symbol(p) for p in name.split(".")])
    return M.Symbol(name)


def py_name(s):
    """The identifier a CL symbol denotes on the Python side.

    SBCL printed under ``readtable-case :invert``, so the name already reads
    the way the programmer wrote it; Hy's mangler handles the rest.
    """
    # Packages are not implemented: a symbol is known by its name alone.  That
    # is what lets a library written in its own package compile at all.
    return s.name


def translate(form):
    """Translate one expanded CL form into a Hy model."""
    if form is NIL:
        return sym("NIL")
    if form is T:
        return sym("T")
    if isinstance(form, Keyword):
        return _datum(form)
    if isinstance(form, Symbol):
        return _var(form)
    if isinstance(form, Cons):
        return _call(form)
    return _literal(form)


# ---------------------------------------------------------------- atoms


def _literal(x):
    if isinstance(x, bool):
        return sym("T") if x else sym("NIL")
    if isinstance(x, int):
        return M.Integer(x)
    if isinstance(x, float):
        return M.Float(x)
    if isinstance(x, Fraction):
        # a Common Lisp rational literal; Python has no syntax for one
        return M.Expression(
            [sym("cl-div"), M.Integer(x.numerator), M.Integer(x.denominator)]
        )
    if isinstance(x, complex):
        return M.Complex(x)
    if isinstance(x, str):
        return M.String(x)
    if isinstance(x, list):  # simple vector
        return M.List([translate(e) for e in x])
    raise TranslationError(f"cannot translate literal {x!r}")


def _var(s):
    name = s.name
    if _fast and name in FAST_RUNTIME:
        return sym(FAST_RUNTIME[name])
    if name in RUNTIME:
        return sym(RUNTIME[name])
    return ref(py_name(s))


def _head_name(s):
    name = s.name
    if _fast:
        if _approx and name in FAST_APPROX_SPECIAL:
            return FAST_APPROX_SPECIAL[name]
        if name in FAST_SPECIAL:
            return FAST_SPECIAL[name]
        if name in FAST_RUNTIME:
            return FAST_RUNTIME[name]
    if name in LOOP_SPECIAL:
        return LOOP_SPECIAL[name]
    if name in SPECIAL:
        return SPECIAL[name]
    if name in RUNTIME:
        return RUNTIME[name]
    if name in OPERATORS:
        return name
    if name in OPERATORS_RENAMED:
        return OPERATORS_RENAMED[name]
    return py_name(s)


# ---------------------------------------------------------------- compounds


def _is_setf_aref(form):
    """(funcall (function (setf aref)) value array index...)"""
    first = form.cdr.car if isinstance(form.cdr, Cons) else None
    if not (isinstance(first, Cons) and isinstance(first.car, Symbol)
            and first.car.name == "function"):
        return False
    place = first.cdr.car if isinstance(first.cdr, Cons) else None
    return (isinstance(place, Cons) and isinstance(place.car, Symbol)
            and place.car.name == "setf"
            and isinstance(place.cdr, Cons) and isinstance(place.cdr.car, Symbol)
            and place.cdr.car.name == "aref")


SPECIALS = set()

# In fast mode the Lisp value representation is dropped: predicates return
# Python booleans, conditionals test Python truth, and arithmetic is Python's.
# Python's operator spellings as Hy writes them; the rest are the same token
_PY_OP_HY = {"not in": "not-in", "is not": "is-not"}

FAST_SPECIAL = {"if": "cl-if-fast", "defun": "cl-defun-fast"}
# a self-tail-recursive defun compiles to a loop instead of the block form
LOOP_SPECIAL = {"%defun-loop": "cl-defun-loop"}
FAST_APPROX_SPECIAL = {"defun": "cl-defun-approx"}
FAST_RUNTIME = {
    "=": "=", "/=": "!=", "<": "<", ">": ">", "<=": "<=", ">=": ">=",
    "+": "+", "-": "-", "*": "*", "/": "/",
    "mod": "%", "not": "not", "expt": "**", "float": "float",
    "aref": "get",
}
_fast = False
_approx = False


def _spec_declaration(body):
    """Read (declare (spec :args p... :ret p :fn p :test n)) from a body."""
    for form in body:
        if not (isinstance(form, Cons) and isinstance(form.car, Symbol)
                and form.car.name == "declare"):
            continue
        for entry in _iter(form.cdr):
            if not (isinstance(entry, Cons) and isinstance(entry.car, Symbol)
                    and entry.car.name == "spec"):
                continue
            spec = {"args": [], "ret": None, "fn": None, "test": 0}
            key = None
            for item in _iter(entry.cdr):
                if isinstance(item, Keyword):
                    key = item.name.lower()
                    continue
                if key == "args":
                    spec["args"].append(item)
                elif key in ("ret", "fn"):
                    spec[key] = item
                elif key == "test":
                    spec["test"] = item if isinstance(item, int) else 0
            return spec
    return None


# ---------------------------------------------------------- self-tail calls
#
# Python has no tail-call optimisation, so a function that calls itself in
# tail position grows the stack and dies at a few thousand frames.  A call to
# *itself* in tail position, however, is just a loop: rebind the parameters
# and go round again.  Mutual recursion is not covered and still has Python's
# limit, which the documentation says.
#
# The rewrite marks each tail position of the body -- a self call becomes
# %TAIL-RECUR, anything else %TAIL-RETURN -- and cl.hy wraps the result in a
# loop.  It is applied only when it is certainly safe (see _tail_safe).

_TAIL_UNSAFE = frozenset({
    # a tail position inside these is not a tail position at all, or the
    # parameters may be captured, so we decline rather than analyse further
    "unwind-protect", "tagbody", "go", "catch", "throw",
    "flet", "labels", "lambda", "function", "symbol-macrolet",
    "handler-case", "handler-bind", "restart-case", "restart-bind",
    "multiple-value-bind", "py-with", "cl-py-with",
})


def _subforms(x):
    """Every cons in the tree, outermost first."""
    if isinstance(x, Cons):
        yield x
        yield from _subforms(x.car)
        yield from _subforms(x.cdr)


def _mklist(items):
    out = NIL
    for x in reversed(items):
        out = Cons(x, out)
    return out


def _tail_safe(fname, lam, body):
    """May the body of FNAME be turned into a loop?

    Conservative on purpose: anything that could make a marked position not
    really a tail position, or could capture a parameter in a closure, or
    could re-enter the implicit block, disqualifies the function.
    """
    params = list(_iter(lam))
    if any(isinstance(p, Symbol) and p.name.startswith("&") for p in params):
        return None                      # &optional/&rest/&key: not worth it
    if not all(isinstance(p, Symbol) for p in params):
        return None
    for cons in _subforms(_mklist(body)):
        if not isinstance(cons.car, Symbol):
            continue
        op = cons.car.name
        if op in _TAIL_UNSAFE:
            return None
        if op == "return-from":
            target = cons.cdr.car if isinstance(cons.cdr, Cons) else None
            if isinstance(target, Symbol) and target.name == fname:
                return None              # re-enters the block we are removing
        if op == "setq":
            # assigning a parameter is fine, but assigning the function's own
            # name would make the self call not a self call
            for i, x in enumerate(_iter(cons.cdr)):
                if i % 2 == 0 and isinstance(x, Symbol) and x.name == fname:
                    return None
    return params


def _mark_tails(form, fname, params):
    """Mark the tail positions of FORM.  Returns (new form, found a self call)."""
    if isinstance(form, Cons) and isinstance(form.car, Symbol):
        op = form.car.name
        args = list(_iter(form.cdr))
        if op in ("progn", "locally") and args:
            new, found = _mark_tails(args[-1], fname, params)
            return Cons(form.car, _mklist(args[:-1] + [new])), found
        if op == "if" and len(args) >= 2:
            then, f1 = _mark_tails(args[1], fname, params)
            if len(args) >= 3:
                els, f2 = _mark_tails(args[2], fname, params)
                return Cons(form.car, _mklist([args[0], then, els])), f1 or f2
            return Cons(form.car, _mklist([args[0], then])), f1
        if op in ("let", "let*", "block") and len(args) >= 2:
            new, found = _mark_tails(args[-1], fname, params)
            return Cons(form.car, _mklist(args[:-1] + [new])), found
        if op == "the" and len(args) == 2:
            new, found = _mark_tails(args[1], fname, params)
            return Cons(form.car, _mklist([args[0], new])), found
        if op == fname and len(args) == len(params):
            return (Cons(Symbol("%tail-recur"),
                         _mklist([_mklist(params)] + args)), True)
    return Cons(Symbol("%tail-return"), _mklist([form])), False


def _loop_body(fname, lam, body):
    """The body rewritten as a loop, or None if the rewrite does not apply."""
    params = _tail_safe(fname, lam, body)
    if params is None or not body:
        return None
    head, last = body[:-1], body[-1]
    if isinstance(last, Cons) and isinstance(last.car, Symbol) \
            and last.car.name == "declare":
        return None                      # a body that is only declarations
    new, found = _mark_tails(last, fname, params)
    if not found:
        return None
    return head + [new]


def _optimize_quality(body, quality_name, default):
    """The level of one (optimize (QUALITY n)) declaration in BODY."""
    for form in body:
        if not (isinstance(form, Cons) and isinstance(form.car, Symbol)
                and form.car.name == "declare"):
            continue
        for entry in _iter(form.cdr):
            if not (isinstance(entry, Cons) and isinstance(entry.car, Symbol)
                    and entry.car.name == "optimize"):
                continue
            for quality in _iter(entry.cdr):
                if isinstance(quality, Symbol) and quality.name == quality_name:
                    return 3            # a bare quality name means level 3
                if isinstance(quality, Cons) and isinstance(quality.car, Symbol) \
                        and quality.car.name == quality_name:
                    level = quality.cdr.car if isinstance(quality.cdr, Cons) else 3
                    if isinstance(level, int):
                        return level
    return default


def _safety_level(body):
    """The (optimize (safety n)) level, defaulting to 1 as Common Lisp does."""
    return _optimize_quality(body, "safety", 1)


def _fast_declared(body):
    """Does the body ask for speed?  (declare (optimize (speed 3)))."""
    return _optimize_quality(body, "speed", 1) >= 3


def _approx_declared(body):
    """Does the body relax floating-point accuracy?

    ANSI Common Lisp lets an implementation define optimize qualities of its
    own, so the permission to reassociate float arithmetic is spelled the way
    every other back-end instruction is:

        (declare (optimize (speed 3) (float-accuracy 0)))

    At the default level the arithmetic is left exactly as written.
    """
    return _optimize_quality(body, "float-accuracy", 3) == 0


def _record_declaim(rest):
    """(declaim (ftype (function (arg-types) return-type) name ...))."""
    for spec in _iter(rest):
        if not (isinstance(spec, Cons) and isinstance(spec.car, Symbol)
                and spec.car.name == "ftype"):
            continue
        signature = spec.cdr.car
        names = list(_iter(spec.cdr.cdr))
        if not isinstance(signature, Cons):
            continue
        parts = list(_iter(signature))
        if len(parts) < 3:
            continue
        py = _python_type(parts[2])
        if py is None:
            continue
        for n in names:
            if isinstance(n, Symbol):
                RETURN_TYPES[n.name] = py


def _assigned_specials(x, found):
    """Special variables a body assigns, so the function can declare them."""
    if not isinstance(x, Cons):
        return found
    head = x.car
    if isinstance(head, Symbol) and head.name in ("setq", "setf"):
        target = x.cdr.car if isinstance(x.cdr, Cons) else None
        if isinstance(target, Symbol) and target.name in SPECIALS:
            found.add(target.name)
    node = x
    while isinstance(node, Cons):
        _assigned_specials(node.car, found)
        node = node.cdr
    return found


def _call(form):
    global _fast, _approx
    head = form.car
    if isinstance(head, Symbol):
        name = head.name
        if name in ("defvar", "defparameter"):
            target = form.cdr.car
            if isinstance(target, Symbol):
                SPECIALS.add(target.name)
        if name == "quote":
            return _datum(form.cdr.car)
        if name == "the":  # (the type value) -- the type is advisory
            return translate(form.cdr.cdr.car)
        if name == "declare":
            return M.Expression([sym("cl-declare")])
        # On the fast path the Lisp value representation is gone and the
        # arithmetic is Python's already, so the wrappers frompy emits to
        # preserve Python semantics collapse into the operators themselves.
        # Numba could not call them anyway.
        if _fast and name == "py-truthy":
            return translate(form.cdr.car)
        if _fast and name in ("py-binop", "py-unop"):
            parts = list(_iter(form.cdr))
            if parts and isinstance(parts[0], str):
                op = _PY_OP_HY.get(parts[0], parts[0])
                return M.Expression([sym(op)] + [translate(a) for a in parts[1:]])
        if name == "funcall" and _is_setf_aref(form):
            args = list(_iter(form.cdr))
            return M.Expression([sym("cl-aset")] + [translate(a) for a in args[1:]])
        if name == "symbol-macrolet":
            return translate(_expand_symbol_macrolet(form))
        args = _args(form.cdr, name)
        if name == "declaim":
            _record_declaim(form.cdr)
            return M.Expression([sym("cl-declare")])
        if name == "defun":
            raw = list(_iter(form.cdr))
            spec = _spec_declaration(raw[2:]) if len(raw) > 2 else None
            if spec is not None and _safety_level(raw[2:]) > 0:
                return _checked_defun(form, raw, spec)
            if _fast_declared(raw[2:]) and not _fast:
                _fast, _approx = True, _approx_declared(raw[2:])
                try:
                    return _call(form)
                finally:
                    _fast, _approx = False, False
            if len(raw) > 2 and isinstance(raw[0], Symbol):
                looped = _loop_body(raw[0].name, raw[1], raw[2:])
                if looped is not None:
                    form = Cons(form.car, _mklist([raw[0], raw[1]] + looped))
                    args = _args(form.cdr, name)
                    head = Symbol("%defun-loop")   # name stays "defun": same shape
            types = _declared_types(raw[2:]) if len(raw) > 2 else {}
            if types:
                args[1] = _annotate_params(args[1], types)
            ret = RETURN_TYPES.get(raw[0].name) if isinstance(raw[0], Symbol) else None
            if ret:
                args[0] = _annotate(args[0], ret)
        if name in ("defun", "lambda", "defmethod"):
            specials = sorted(_assigned_specials(form.cdr, set()))
            if specials:
                raw = list(_iter(form.cdr))
                if name == "defun":
                    fixed = 2
                elif name == "lambda":
                    fixed = 1
                else:  # defmethod: the body starts after the lambda list
                    fixed = 3 if len(raw) > 1 and isinstance(raw[1], Symbol) else 2
                args = (
                    args[:fixed]
                    + [M.Expression([sym("cl-globals")] + [sym(s) for s in specials])]
                    + args[fixed:]
                )
        head_model = ref(_head_name(head))
        if name in SPECIAL or name in _STRUCTURAL:
            return M.Expression([head_model] + args)
        return _ordered_call(head_model, list(_iter(form.cdr)), args)
    if isinstance(head, Cons):  # ((lambda ...) args) and friends
        return M.Expression([translate(head)] + _args(form.cdr, None))
    raise TranslationError(f"cannot translate call head {head!r}")


# SYMBOL-MACROLET is a compile-time substitution, so it is discharged here
# rather than given a runtime counterpart.  Pattern matchers lean on it: this
# is what trivia wraps every MATCH in.


def _expand_symbol_macrolet(form):
    from .runtime import from_iterable

    subs = {}
    for b in _iter(form.cdr.car):
        parts = list(_iter(b))
        subs[parts[0]] = parts[1] if len(parts) > 1 else NIL
    body = [_substitute(f, subs) for f in _iter(form.cdr.cdr)]
    return from_iterable([Symbol("progn", "COMMON-LISP")] + body)


def _substitute(x, subs):
    from .runtime import from_iterable

    if isinstance(x, Symbol):
        return subs.get(x, x)
    if not isinstance(x, Cons):
        return x
    if isinstance(x.car, Symbol) and x.car.name == "quote":
        return x
    items, node = [], x
    while isinstance(node, Cons):
        items.append(_substitute(node.car, subs))
        node = node.cdr
    return from_iterable(items, _substitute(node, subs))


def _checked_defun(form, raw, spec):
    """Compile a DEFUN whose SPEC declaration asks for contract checking.

    How much is checked is the SAFETY level: 3 checks the arguments, the
    return value and the relation between them; 1 checks the arguments; 0
    generates nothing, which is the fast path.
    """
    level = _safety_level(raw[2:])
    body = [translate(f) for f in raw[2:]]
    return M.Expression(
        [
            sym("cl-defun-checked"),
            _name(raw[0]),
            _bindings(raw[1]),
            M.Integer(level),
            M.List([translate(p) for p in spec["args"]]),
            translate(spec["ret"]) if spec["ret"] is not None else sym("None"),
            translate(spec["fn"]) if spec["fn"] is not None else sym("None"),
        ]
        + body
    )


# Forms that assign.  If one appears as an argument, Hy hoists its statements
# above the call, which would let a later argument's side effect be seen by an
# earlier one -- Common Lisp evaluates arguments strictly left to right.  When
# that can happen we bind the earlier arguments to temporaries first.
_MUTATORS = {
    "setq", "setf", "psetq", "psetf", "incf", "decf", "push", "pop",
    "rotatef", "shiftf", "remf", "rplaca", "rplacd",
}

_temp_counter = 0


def _mutates(x):
    if not isinstance(x, Cons):
        return False
    head = x.car
    if isinstance(head, Symbol) and head.name in _MUTATORS:
        return True
    node = x
    while isinstance(node, Cons):
        if _mutates(node.car):
            return True
        node = node.cdr
    return False


def _ordered_call(head_model, originals, translated):
    """Force left-to-right evaluation when a later argument assigns."""
    global _temp_counter
    if len(translated) < 2 or not any(_mutates(a) for a in originals[1:]):
        return M.Expression([head_model] + translated)
    last = max(i for i, a in enumerate(originals) if _mutates(a))
    bindings, names = [], []
    for i, model in enumerate(translated):
        if i < last:
            _temp_counter += 1
            tmp = M.Symbol(f"_ord{_temp_counter}")
            bindings.extend([tmp, model])
            names.append(tmp)
        else:
            names.append(model)
    return M.Expression(
        [M.Symbol("let"), M.List(bindings), M.Expression([head_model] + names)]
    )


# Operators whose arguments are binding forms rather than expressions; the
# macros in cl.hy destructure them, so we pass the shape through untouched.
_STRUCTURAL = {
    "let": {1: "bindings"},
    "let*": {1: "bindings"},
    "flet": {1: "fbindings"},
    "labels": {1: "fbindings"},
    "lambda": {1: "bindings"},
    "defun": {1: "name", 2: "bindings"},
    "%defun-loop": {1: "name", 2: "bindings"},
    "block": {1: "name"},
    "return-from": {1: "name"},
    "go": {1: "name"},
    "function": {1: "fname"},
    "multiple-value-bind": {1: "names"},
    "%tail-recur": {1: "names"},
    "py-for": {1: "binding"},
    "py-del": "all-names",
    "py-import-star": {1: "name"},
    "py-global": "all-names",
    "py-nonlocal": "all-names",
    "handler-bind": {1: "bindings"},
    "tagbody": "tags",
    "py-import": {1: "name"},
    "py-import-as": {1: "name", 2: "name"},
    "destructuring-bind": {1: "raw"},
    "py-with": {1: "bindings"},
    "defstruct": "raw",
    "defclass": {1: "name", 2: "raw", 3: "raw"},
    "defmethod": {1: "name", 2: "raw", 3: "raw"},
    "defgeneric": {1: "name", 2: "raw"},
    "defvar": {1: "name"},
    "defun-async": {1: "name", 2: "bindings"},
    "defun-decorated": {2: "name", 3: "bindings"},
    "declaim": "raw",
    "dotimes": {1: "bindings"},
    "dolist": {1: "bindings"},
    "defparameter": {1: "name"},
    "handler-case": "clauses",
    "restart-case": "clauses",
    "define-condition": {1: "name", 2: "raw", 3: "raw"},
}


def _shape_for(name, args):
    """DEFMETHOD's shape depends on whether a qualifier is present, so the
    specialised lambda list -- and the body after it -- shift by one."""
    if name == "defmethod":
        qualified = len(args) > 1 and isinstance(args[1], Symbol)
        return {1: "name", 2: "raw", 3: "raw"} if qualified else {1: "name", 2: "raw"}
    return _STRUCTURAL.get(name)


def _args(rest, head_name):
    args = list(_iter(rest))
    shape = _shape_for(head_name, args)
    out = []
    for i, arg in enumerate(args, start=1):
        if shape == "clauses":
            # (handler-case protected (type (var) body...) ...)
            out.append(translate(arg) if i == 1 else _clause(arg))
        elif shape == "raw":
            out.append(_raw(arg))
        elif shape == "all-names":
            out.append(_name(arg))
        elif shape == "tags":
            # a tagbody body is a mix of tags (bare symbols) and forms
            out.append(sym(py_name(arg)) if isinstance(arg, Symbol) else translate(arg))
        elif isinstance(shape, dict) and i in shape:
            out.append(_STRUCT_KIND[shape[i]](arg))
        else:
            out.append(translate(arg))
    return out


def _name(x):
    """A name position: NIL here is the block named NIL, not the empty list."""
    if isinstance(x, Symbol):
        return ref(py_name(x))
    return translate(x)


# `+` compiles to Python's operator in call position, but `#'+` is a value.
_FUNCTION_VALUE = {"+": "cl-plus", "-": "cl-minus", "*": "cl-times"}


def _fname(x):
    """A function-value position, as in #'car.

    This has to consult the same tables a call head does: `#'equalp` denotes
    the runtime's function just as `(equalp a b)` calls it.
    """
    if isinstance(x, Symbol):
        if x.name in _FUNCTION_VALUE:
            return sym(_FUNCTION_VALUE[x.name])
        if x.name in RUNTIME:
            return sym(RUNTIME[x.name])
    return _name(x)


def _raw(x):
    """Pass a form through as data: DEFSTRUCT's slots are a description."""
    if x is NIL:
        return M.List([])
    if isinstance(x, Symbol):
        return _name(x)
    if isinstance(x, Cons):
        return M.List([_raw(e) for e in _iter(x)])
    return _literal(x)


def _clause(c):
    """A HANDLER-CASE or RESTART-CASE clause: head and variables, then code.

    The head is one condition type, or a list of them -- what Python's
    `except (A, B) as e` needs.
    """
    parts = list(_iter(c))
    head = _names(parts[0]) if isinstance(parts[0], Cons) else _name(parts[0])
    return M.List(
        [head, _names(parts[1] if len(parts) > 1 else NIL)]
        + [translate(f) for f in parts[2:]]
    )


def _names(x):
    return M.List([_name(n) for n in _iter(x)])


def _bindings(x):
    """A LET binding list or lambda list: names stay names, inits are code."""
    out = []
    for b in _iter(x):
        if isinstance(b, Symbol):
            out.append(_name(b))
            continue
        parts = list(_iter(b))
        entry = [_name(parts[0])]
        if len(parts) > 1:
            entry.append(translate(parts[1]))
        out.append(M.List(entry))
    return M.List(out)


def _fbindings(x):
    """An FLET/LABELS binding list: (name lambda-list . body)."""
    out = []
    for b in _iter(x):
        parts = list(_iter(b))
        out.append(
            M.List(
                [_name(parts[0]), _bindings(parts[1])]
                + [translate(f) for f in parts[2:]]
            )
        )
    return M.List(out)


def _binding(x):
    """One (name form) pair, as PY-FOR's iteration spec is."""
    parts = list(_iter(x))
    return M.List([_name(parts[0])] + [translate(e) for e in parts[1:]])


_STRUCT_KIND = {
    "raw": _raw,
    "binding": _binding,
    "name": _name,
    "fname": _fname,
    "names": _names,
    "bindings": _bindings,
    "fbindings": _fbindings,
}


def _iter(x):
    while isinstance(x, Cons):
        yield x.car
        x = x.cdr


# ---------------------------------------------------------------- quoted data
#
# Quoted structure is rebuilt at run time by constructor calls, so that
# interned symbols stay EQ-comparable.


def _datum(x):
    if x is NIL:
        return sym("NIL")
    if x is T:
        return sym("T")
    if isinstance(x, Keyword):
        return M.Expression([sym("cl-keyword"), M.String(x.name)])
    if isinstance(x, Symbol):
        return M.Expression(
            [sym("cl-symbol"), M.String(x.name), M.String(x.package)]
        )
    if isinstance(x, Cons):
        return M.Expression([sym("cl-cons"), _datum(x.car), _datum(x.cdr)])
    return _literal(x)
