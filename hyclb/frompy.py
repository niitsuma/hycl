"""Translate Python back into the Common Lisp that hyclb compiles.

The rest of hyclb runs one way: Common Lisp in, Python bytecode out. This runs
the other way, so that an existing Python program can be brought into the Lisp
and then edited with macros. It differs from py2hy, which emits Hy: the output
here is Common Lisp source, read and macroexpanded by SBCL like any other
`.lisp` file, so a macro can be applied to it immediately.

    python -m hyclb.frompy script.py            # print the Lisp
    python -m hyclb.frompy script.py -o out.lisp

The translation aims at behaviour, not at beauty. Where Common Lisp and Python
agree -- ``+``, ``-``, ``*``, the orderings, ``and``/``or`` returning their
operand -- the Lisp operator is emitted and the output reads as Lisp. Where
they disagree the Python one is emitted explicitly, because a silent change of
meaning is the worst thing a translator can do:

    Python      Common Lisp would give        so we emit
    10 / 4      5/2, an exact rational        (py-binop "/" 10 4)
    a == b      numeric or structural =       (py-binop "==" a b)
    if 0:       0 is true in CL               (if (py-truthy 0) ...)
    not 0       NIL, i.e. false               (py-unop "not" 0)
    0 or 5      0, since 0 is true            (py-or 0 5)

Round-tripping is the test that matters: ``tests/frompy.py`` runs a program as
Python, translates it, compiles the translation with hyclb, runs that, and
compares. Anything this module cannot translate raises `Unsupported` rather
than guessing.
"""

import ast
import sys

from . import translate

__all__ = ["translate_source", "translate_file", "Unsupported"]


_NO_DEFAULT = object()   # distinct from a default that *is* None


class Unsupported(Exception):
    """A Python construct with no faithful translation yet."""


# --------------------------------------------------------------------------
# the s-expression the printer consumes


class Sym(str):
    """A symbol, as opposed to a string literal."""


class Kw(str):
    """A keyword argument name, printed with a leading colon."""


def _atom(x):
    return not isinstance(x, (list, tuple))


# how many elements after the operator belong on its line: a DEFUN keeps its
# name and lambda list there, a DOLIST its iteration spec.
_STICKY = {
    "defun": 2, "defun-async": 2, "defun-decorated": 3, "lambda": 1,
    "dolist": 1, "dotimes": 1, "let": 1, "let*": 1, "block": 1,
    "return-from": 1, "when": 1, "unless": 1, "if": 1, "handler-case": 0,
    "py-with": 1, "setq": 1, "py-class": 2,
    "py-while": 1, "py-for": 1,
}


def render(form, indent=0, width=88):
    """Print a form, breaking long ones across lines."""
    flat = _flat(form)
    if len(flat) + indent <= width or _atom(form) or not form:
        return flat
    head, *rest = form
    if isinstance(head, Sym) and str(head) == "loop":
        return _render_loop(form, indent, width)
    keep = _STICKY.get(str(head), 0) if isinstance(head, Sym) else 0
    first = " ".join([_flat(head)] + [_flat(x) for x in rest[:keep]])
    pad = " " * (indent + 2)
    lines = [first]
    for x in rest[keep:]:
        lines.append(pad + render(x, indent + 2, width))
    return "(" + ("\n".join(lines)) + ")"


_LOOP_KEYWORDS = {"for", "in", "on", "across", "while", "until", "when",
                  "unless", "do", "collect", "append", "sum", "count",
                  "maximize", "minimize", "thereis", "always", "finally",
                  "with", "and", "=", "from", "below", "to", "then", "into"}


def _render_loop(form, indent, width):
    """LOOP reads as prose, so break it at its keywords rather than per item."""
    pad = " " * (indent + 6)
    chunks, current = [], []
    for x in form[1:]:
        if isinstance(x, Sym) and str(x) in _LOOP_KEYWORDS and current:
            chunks.append(current)
            current = [x]
        else:
            current.append(x)
    if current:
        chunks.append(current)
    lines = []
    for i, chunk in enumerate(chunks):
        text = " ".join(render(x, indent + 6, width) for x in chunk)
        lines.append(("(loop " if i == 0 else pad) + text)
    return "\n".join(lines) + ")"


def _flat(form):
    if isinstance(form, Kw):
        return ":" + form
    if isinstance(form, Sym):
        return str(form)
    if isinstance(form, str):
        return '"' + form.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if form is True:
        return "py-true"
    if form is False:
        return "py-false"
    if form is None:
        return "py-none"
    if isinstance(form, float):
        # a Lisp float literal is double only with an exponent marker
        return repr(form) if "e" in repr(form) or "." in repr(form) else repr(form) + ".0"
    if isinstance(form, (int, complex)):
        return repr(form)
    return "(" + " ".join(_flat(x) for x in form) + ")"


# --------------------------------------------------------------------------
# names
#
# py_name hands a symbol's name to Hy unchanged, so a Python identifier can be
# written as itself.  The exception is a name hyclb already means something by:
# `list` and `map` resolve to the Lisp functions, and `t` and `nil` are not
# variables at all.  Those are renamed, and the renaming is reported.

_RESERVED = (
    set(translate.SPECIAL)
    | set(translate.RUNTIME)
    | set(getattr(translate, "OPERATORS", ()))
    | set(getattr(translate, "OPERATORS_RENAMED", ()))
    | {"t", "nil", "T", "NIL", "declare", "declaim", "quote", "the",
       "cond", "when", "unless", "case", "loop", "do", "dolist", "dotimes",
       "let", "let*", "setf", "setq", "defmacro", "lambda", "function",
       "and", "or", "not", "if", "progn", "block", "return-from", "tagbody"}
)


class _Names:
    """Python identifiers, adjusted only where hyclb already owns the name.

    Two kinds of collision, resolved differently.  `print` and `list` mean the
    Lisp functions in hyclb, but the program usually means Python's builtins,
    so those are reached through the `builtins` module -- exact, and the reader
    still sees the name it expects.  A name the program itself binds cannot be
    redirected that way, so it is renamed, and the renaming is reported.

    Which of the two applies depends on scope: a local variable called `list`
    in one function must not turn every other `list` in the file into that
    local.  The caller keeps a stack of the scopes in force.
    """

    def __init__(self, module_scope=()):
        self.module_scope = set(module_scope)
        self.stack = []
        self.renamed = {}
        self.used_builtins = False

    def bound(self, name):
        return name in self.module_scope or any(name in s for s in self.stack)

    def __call__(self, name):
        if name not in _RESERVED:
            return Sym(name)
        if not self.bound(name) and hasattr(_BUILTINS, name):
            self.used_builtins = True
            return Sym("builtins." + name)
        if name not in self.renamed:
            new = name + "_"
            while new in _RESERVED:
                new += "_"
            self.renamed[name] = new
        return Sym(self.renamed[name])


import builtins as _BUILTINS  # noqa: E402


def _scope_names(stmts, owner=None):
    """The names one scope binds: its own, not a nested function's.

    A nested def has its own scope, so the names inside it are not in this
    one; its *name* is.  Parameters of OWNER, when given, belong here.
    """
    out = set()
    if isinstance(owner, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
        a = owner.args
        for group in (a.posonlyargs, a.args, a.kwonlyargs):
            out.update(x.arg for x in group)
        for extra in (a.vararg, a.kwarg):
            if extra:
                out.add(extra.arg)

    def walk(node, top):
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef,
                                  ast.ClassDef)):
                out.add(child.name)
                continue                     # its body is a scope of its own
            if isinstance(child, ast.Lambda):
                continue
            if isinstance(child, ast.Name) and isinstance(child.ctx, ast.Store):
                out.add(child.id)
            elif isinstance(child, ast.alias):
                out.add(child.asname or child.name.split(".")[0])
            elif isinstance(child, ast.ExceptHandler) and child.name:
                out.add(child.name)
            elif isinstance(child, (ast.Global, ast.Nonlocal)):
                out.update(child.names)
            walk(child, False)

    for s in stmts:
        walk(ast.Module(body=[s], type_ignores=[]) if False else s, True)
        if isinstance(s, ast.Name) and isinstance(s.ctx, ast.Store):
            out.add(s.id)
    return out


# --------------------------------------------------------------------------
# operators
#
# Emitted as the Lisp operator when Common Lisp and Python agree, and as an
# explicit py-binop when they do not.  cl_lt and friends are Python's own
# comparisons and chain the way Python chains them, so those stay Lisp.

_LISP_BINOP = {ast.Add: "+", ast.Sub: "-", ast.Mult: "*"}
_PY_BINOP = {
    ast.Div: "/", ast.FloorDiv: "//", ast.Mod: "%", ast.Pow: "**",
    ast.MatMult: "@", ast.LShift: "<<", ast.RShift: ">>",
    ast.BitAnd: "&", ast.BitOr: "|", ast.BitXor: "^",
}
_LISP_CMP = {ast.Lt: "<", ast.LtE: "<=", ast.Gt: ">", ast.GtE: ">="}
_PY_CMP = {
    ast.Eq: "==", ast.NotEq: "!=", ast.In: "in", ast.NotIn: "not in",
    ast.Is: "is", ast.IsNot: "is not",
}
_AUG = {**{k: v for k, v in _LISP_BINOP.items()}, **_PY_BINOP}


class Translator(ast.NodeVisitor):
    def __init__(self, module_scope=()):
        self.name = _Names(module_scope)
        self.blocks = []          # innermost `return` target
        self.loops = []           # the innermost loop's "did it break" flag
        self.scopes = self.name.stack
        self.classes = []         # enclosing class names, for super()
        self.selves = []          # each function's first parameter

    # -- entry ------------------------------------------------------------

    def module(self, tree):
        return [self.stmt(s) for s in tree.body]

    def generic_visit(self, node):
        raise Unsupported(f"{type(node).__name__} at line "
                          f"{getattr(node, 'lineno', '?')}")

    # -- helpers ----------------------------------------------------------

    def bi(self, name):
        """A Python builtin *we* reference.  Always through `builtins`: `format`
        and `dict` mean the Lisp functions to hyclb."""
        self.name.used_builtins = True
        return Sym("builtins." + name)

    def cond(self, node):
        """A Python condition: 0 and the empty list are false."""
        form = self.expr(node)
        if isinstance(form, list) and form[:1] == [Sym("py-truthy")]:
            return form
        return [Sym("py-truthy"), form]

    def body(self, stmts):
        return [self.stmt(s) for s in stmts]

    def seq(self, stmts):
        """A statement sequence in a position that wants one form."""
        forms = self.body(stmts)
        return forms[0] if len(forms) == 1 else [Sym("progn"), *forms]

    def expr(self, node):
        method = getattr(self, "e_" + type(node).__name__, None)
        if method is None:
            raise Unsupported(f"expression {type(node).__name__} at line "
                              f"{getattr(node, 'lineno', '?')}")
        return method(node)

    def stmt(self, node):
        method = getattr(self, "s_" + type(node).__name__, None)
        if method is None:
            raise Unsupported(f"statement {type(node).__name__} at line "
                              f"{getattr(node, 'lineno', '?')}")
        return method(node)

    # -- expressions ------------------------------------------------------

    def e_Constant(self, node):
        v = node.value
        if v is Ellipsis:
            return self.bi("Ellipsis")
        if isinstance(v, bytes):
            return [Sym("py-method"), v.decode("latin-1"), "encode", "latin-1"]
        return v

    def e_Name(self, node):
        return self.name(node.id)

    def e_Attribute(self, node):
        dotted = self._dotted(node)
        if dotted is not None:
            return Sym(dotted)
        return [Sym("py-attr"), self.expr(node.value), node.attr]

    def _dotted(self, node):
        """`numpy.linalg.norm` can be one symbol; `(f()).x` cannot."""
        parts = []
        while isinstance(node, ast.Attribute):
            parts.append(node.attr)
            node = node.value
        if isinstance(node, ast.Name) and node.id not in _RESERVED:
            parts.append(node.id)
            return ".".join(reversed(parts))
        return None

    def e_Call(self, node):
        if isinstance(node.func, ast.Name) and node.func.id == "super" \
                and not node.args and not node.keywords:
            # Python's zero-argument super() reads a __class__ cell that only
            # its own class-body compilation creates.  The two-argument form
            # says the same thing and needs nothing hidden.
            if not self.classes or not self.selves or self.selves[-1] is None:
                raise Unsupported("super() outside a method")
            return [Sym("py-call"), self.bi("super"),
                    self.classes[-1], self.selves[-1]]
        starred = any(isinstance(a, ast.Starred) for a in node.args) or \
            any(k.arg is None for k in node.keywords)
        func = self.expr(node.func)
        if starred:
            args, extra = [], []
            for a in node.args:
                if isinstance(a, ast.Starred):
                    extra.append(self.expr(a.value))
                else:
                    args.append(self.expr(a))
            positional = [Sym("py-list"), [Sym("list"), *args]]
            for x in extra:
                positional = [Sym("py-binop"), "+", positional,
                              [Sym("py-list"), x]]
            pairs, merges = [], []
            for k in node.keywords:
                if k.arg is None:
                    merges.append(self.expr(k.value))
                else:
                    pairs += [k.arg, self.expr(k.value)]
            kwargs = [Sym("py-dict"), *pairs]
            for m in merges:
                kwargs = [Sym("py-method"), kwargs, "__or__", m]
            return [Sym("py-call-ex"), func, positional, kwargs]
        out = [Sym("py-call"), func, *[self.expr(a) for a in node.args]]
        for k in node.keywords:
            out += [Kw(k.arg), self.expr(k.value)]
        return out

    def e_BinOp(self, node):
        left, right = self.expr(node.left), self.expr(node.right)
        kind = type(node.op)
        if kind in _LISP_BINOP:
            return [Sym(_LISP_BINOP[kind]), left, right]
        if kind in _PY_BINOP:
            return [Sym("py-binop"), _PY_BINOP[kind], left, right]
        raise Unsupported(f"operator {kind.__name__}")

    def e_UnaryOp(self, node):
        table = {ast.Not: "not", ast.USub: "-", ast.UAdd: "+", ast.Invert: "~"}
        kind = type(node.op)
        if kind not in table:
            raise Unsupported(f"unary {kind.__name__}")
        return [Sym("py-unop"), table[kind], self.expr(node.operand)]

    def e_BoolOp(self, node):
        head = "py-and" if isinstance(node.op, ast.And) else "py-or"
        return [Sym(head), *[self.expr(v) for v in node.values]]

    def e_Compare(self, node):
        # cl_lt and friends chain exactly as Python does, so a < b < c is one
        # form and b is evaluated once.  The Python-only comparisons cannot
        # chain, so a mixed chain is refused rather than mistranslated.
        kinds = [type(o) for o in node.ops]
        parts = [self.expr(node.left)] + [self.expr(c) for c in node.comparators]
        if len(kinds) == 1:
            kind = kinds[0]
            if kind in _LISP_CMP:
                return [Sym("py-truthy"), [Sym(_LISP_CMP[kind]), *parts]]
            if kind in _PY_CMP:
                return [Sym("py-binop"), _PY_CMP[kind], *parts]
            raise Unsupported(f"comparison {kind.__name__}")
        if all(k in _LISP_CMP for k in kinds) and len(set(kinds)) == 1:
            return [Sym("py-truthy"), [Sym(_LISP_CMP[kinds[0]]), *parts]]
        return self._mixed_chain(kinds, parts)

    def _mixed_chain(self, kinds, parts):
        """a < b == c: each operand once, and c untouched if a < b is false.

        Built inside out as nested LETs, so the short-circuiting is the LET
        nesting rather than a repeated expression.
        """
        self._chain_counter = getattr(self, "_chain_counter", 0) + 1
        names = [Sym(f"%c{self._chain_counter}_{i}") for i in range(len(parts))]

        def step(i):
            kind = kinds[i]
            if kind in _LISP_CMP:
                test = [Sym("py-truthy"),
                        [Sym(_LISP_CMP[kind]), names[i], names[i + 1]]]
            elif kind in _PY_CMP:
                test = [Sym("py-binop"), _PY_CMP[kind], names[i], names[i + 1]]
            else:
                raise Unsupported(f"comparison {kind.__name__}")
            if i + 1 == len(kinds):
                return test
            return [Sym("py-and"), test,
                    [Sym("let"), [[names[i + 2], parts[i + 2]]], step(i + 1)]]

        return [Sym("let"), [[names[0], parts[0]], [names[1], parts[1]]], step(0)]

    def e_IfExp(self, node):
        return [Sym("if"), self.cond(node.test),
                self.expr(node.body), self.expr(node.orelse)]

    def e_Lambda(self, node):
        defaults = self._defaults(node.args)
        self.scopes.append(_scope_names([], node))
        self.selves.append(self._first_param(node))
        try:
            return [Sym("lambda"), self._lambda_list(node.args, defaults),
                    self.expr(node.body)]
        finally:
            self.scopes.pop()
            self.selves.pop()

    def _elements(self, elts):
        """A display's elements, splicing any starred one by concatenation."""
        if not any(isinstance(e, ast.Starred) for e in elts):
            return [Sym("py-list"), [Sym("list"), *[self.expr(e) for e in elts]]]
        chunks, plain = [], []
        for e in elts:
            if isinstance(e, ast.Starred):
                if plain:
                    chunks.append([Sym("py-list"), [Sym("list"), *plain]])
                    plain = []
                chunks.append([Sym("py-list"), self.expr(e.value)])
            else:
                plain.append(self.expr(e))
        if plain:
            chunks.append([Sym("py-list"), [Sym("list"), *plain]])
        out = chunks[0]
        for c in chunks[1:]:
            out = [Sym("py-binop"), "+", out, c]
        return out

    def e_List(self, node):
        return self._elements(node.elts)

    def e_Tuple(self, node):
        return [Sym("py-tuple"), self._elements(node.elts)]

    def e_Set(self, node):
        return [Sym("py-set"), [Sym("list"), *[self.expr(e) for e in node.elts]]]

    def e_Dict(self, node):
        pairs = []
        for k, v in zip(node.keys, node.values):
            if k is None:
                raise Unsupported("** in a dict display")
            pairs += [self.expr(k), self.expr(v)]
        return [Sym("py-dict"), *pairs]

    def e_Subscript(self, node):
        return [Sym("py-getitem"), self.expr(node.value),
                self.expr(node.slice)]

    def e_Slice(self, node):
        part = lambda x: Sym("nil") if x is None else self.expr(x)  # noqa: E731
        return [Sym("py-slice"), part(node.lower), part(node.upper),
                part(node.step)]

    def e_Starred(self, node):
        raise Unsupported("* outside a call")

    def e_JoinedStr(self, node):
        pieces = []
        for v in node.values:
            if isinstance(v, ast.Constant):
                pieces.append(v.value)
            else:
                pieces.append(self.expr(v))
        return [Sym("py-method"), "", "join",
                [Sym("py-list"), [Sym("list"), *pieces]]]

    def e_FormattedValue(self, node):
        value = self.expr(node.value)
        if node.conversion == 114:
            value = [Sym("py-call"), self.bi("repr"), value]
        elif node.conversion == 97:
            value = [Sym("py-call"), self.bi("ascii"), value]
        spec = ""
        if node.format_spec is not None:
            inner = node.format_spec
            if not (isinstance(inner, ast.JoinedStr) and len(inner.values) == 1
                    and isinstance(inner.values[0], ast.Constant)):
                raise Unsupported("a computed format spec")
            spec = inner.values[0].value
        return [Sym("py-call"), self.bi("format"), value, spec]

    def e_NamedExpr(self, node):
        """The walrus: assign, then be the value."""
        return [Sym("progn"), self._assign(node.target, self.expr(node.value)),
                self.expr(node.target)]

    def e_Yield(self, node):
        if node.value is None:
            return [Sym("py-yield")]
        return [Sym("py-yield"), self.expr(node.value)]

    def e_YieldFrom(self, node):
        return [Sym("py-yield-from"), self.expr(node.value)]

    def e_Await(self, node):
        return [Sym("py-await"), self.expr(node.value)]

    def e_ListComp(self, node):
        return [Sym("py-list"), self._comp(node, node.elt)]

    def e_GeneratorExp(self, node):
        return [Sym("py-list"), self._comp(node, node.elt)]

    def e_SetComp(self, node):
        return [Sym("py-set"), self._comp(node, node.elt)]

    def e_DictComp(self, node):
        pair = [Sym("py-tuple"), [Sym("list"), self.expr(node.key),
                                  self.expr(node.value)]]
        return [Sym("py-call"), self.bi("dict"), self._comp(node, None, pair)]

    def _comp(self, node, elt, ready=None):
        """A comprehension as LOOP ... COLLECT, one clause per generator."""
        if len(node.generators) != 1:
            raise Unsupported("a comprehension with more than one for")
        gen = node.generators[0]
        if gen.is_async:
            raise Unsupported("an async comprehension")
        value = ready if ready is not None else self.expr(elt)
        if isinstance(gen.target, (ast.Tuple, ast.List)):
            # destructure inside the guard: LOOP evaluates WHEN before COLLECT,
            # so the unpacked names are in scope for both
            item = Sym("%c")
            tests = [self.cond(c) for c in gen.ifs] or [Sym("t")]
            guard = tests[0] if len(tests) == 1 else [Sym("py-and"), *tests]
            return [Sym("loop"), Sym("for"), item, Sym("in"),
                    [Sym("py-list"), self.expr(gen.iter)],
                    Sym("when"), [Sym("progn"),
                                  self._assign(gen.target, item), guard],
                    Sym("collect"), value]
        form = [Sym("loop"), Sym("for"), self._target(gen.target),
                Sym("in"), [Sym("py-list"), self.expr(gen.iter)]]
        for cond in gen.ifs:
            form += [Sym("when"), self.cond(cond)]
        form += [Sym("collect"), value]
        return form

    # -- statements -------------------------------------------------------

    def s_Expr(self, node):
        return self.expr(node.value)

    def s_Pass(self, node):
        return Sym("nil")

    def s_Assign(self, node):
        value = self.expr(node.value)
        if len(node.targets) == 1:
            return self._assign(node.targets[0], value)
        # a = b = value: bind once, then set each target
        tmp = Sym("%v")
        return [Sym("let"), [[tmp, value]],
                *[self._assign(t, tmp) for t in node.targets]]

    def s_AnnAssign(self, node):
        if node.value is None:
            return Sym("nil")           # a bare annotation declares nothing
        return self._assign(node.target, self.expr(node.value))

    def s_AugAssign(self, node):
        kind = type(node.op)
        if kind not in _AUG:
            raise Unsupported(f"augmented {kind.__name__}")
        target = self.expr(node.target)
        if kind in _LISP_BINOP:
            value = [Sym(_LISP_BINOP[kind]), target, self.expr(node.value)]
        else:
            value = [Sym("py-binop"), _PY_BINOP[kind], target,
                     self.expr(node.value)]
        return self._assign(node.target, value)

    def _assign(self, target, value):
        if isinstance(target, ast.Name):
            return [Sym("setq"), self.name(target.id), value]
        if isinstance(target, ast.Attribute):
            return [Sym("py-set-attr"), self.expr(target.value),
                    target.attr, value]
        if isinstance(target, ast.Subscript):
            return [Sym("py-setitem"), self.expr(target.value),
                    self.expr(target.slice), value]
        if isinstance(target, (ast.Tuple, ast.List)):
            if any(isinstance(e, ast.Starred) for e in target.elts):
                raise Unsupported("starred unpacking")
            tmp = Sym("%unpack")
            out = [Sym("let"), [[tmp, [Sym("py-list"), value]]]]
            for i, e in enumerate(target.elts):
                out.append(self._assign(e, [Sym("py-getitem"), tmp, i]))
            return out
        raise Unsupported(f"assignment to {type(target).__name__}")

    def _target(self, node):
        """A for-loop target: a name, or a name list to destructure."""
        if isinstance(node, ast.Name):
            return self.name(node.id)
        raise Unsupported("a for-loop target that is not a plain name")

    def s_If(self, node):
        if node.orelse:
            return [Sym("if"), self.cond(node.test),
                    self.seq(node.body), self.seq(node.orelse)]
        return [Sym("when"), self.cond(node.test), *self.body(node.body)]

    def s_While(self, node):
        flag = self._loop_flag(node)
        self.loops.append(flag)
        try:
            loop = [Sym("py-while"), self.cond(node.test), *self.body(node.body)]
        finally:
            self.loops.pop()
        return self._with_else(loop, flag, node.orelse)

    def s_For(self, node):
        flag = self._loop_flag(node)
        self.loops.append(flag)
        try:
            if isinstance(node.target, (ast.Tuple, ast.List)):
                item = Sym("%item")
                loop = [Sym("py-for"), [item, self.expr(node.iter)],
                        self._assign(node.target, item), *self.body(node.body)]
            else:
                loop = [Sym("py-for"),
                        [self._target(node.target), self.expr(node.iter)],
                        *self.body(node.body)]
        finally:
            self.loops.pop()
        return self._with_else(loop, flag, node.orelse)

    def _loop_flag(self, node):
        """A loop with an else clause needs to know whether it broke out."""
        if not node.orelse:
            return None
        self._flag_counter = getattr(self, "_flag_counter", 0) + 1
        return Sym(f"%broke{self._flag_counter}")

    def _with_else(self, loop, flag, orelse):
        if flag is None:
            return loop
        return [Sym("let"), [[flag, False]], loop,
                [Sym("unless"), [Sym("py-truthy"), flag], *self.body(orelse)]]

    def s_Break(self, node):
        if not self.loops:
            raise Unsupported("break outside a loop")
        flag = self.loops[-1]
        if flag is None:
            return [Sym("py-break")]
        return [Sym("progn"), [Sym("setq"), flag, True], [Sym("py-break")]]

    def s_Continue(self, node):
        if not self.loops:
            raise Unsupported("continue outside a loop")
        return [Sym("py-continue")]

    def s_Return(self, node):
        value = Sym("nil") if node.value is None else self.expr(node.value)
        if not self.blocks:
            raise Unsupported("return outside a function")
        return [Sym("return-from"), self.blocks[-1], value]

    def s_Global(self, node):
        return [Sym("py-global"), *[self.name(n) for n in node.names]]

    def s_Nonlocal(self, node):
        return [Sym("py-nonlocal"), *[self.name(n) for n in node.names]]

    def s_Raise(self, node):
        if node.exc is None:
            return [Sym("py-reraise")]
        if node.cause is not None:
            return [Sym("py-raise"), self.expr(node.exc), self.expr(node.cause)]
        return [Sym("py-raise"), self.expr(node.exc)]

    def s_Assert(self, node):
        message = self.expr(node.msg) if node.msg else "assertion failed"
        return [Sym("unless"), self.cond(node.test),
                [Sym("py-raise"),
                 [Sym("py-call"), self.bi("AssertionError"), message]]]

    def s_Delete(self, node):
        out = []
        for t in node.targets:
            if isinstance(t, ast.Subscript):
                out.append([Sym("py-method"), self.expr(t.value),
                            "__delitem__", self.expr(t.slice)])
            elif isinstance(t, ast.Attribute):
                out.append([Sym("py-call"), self.bi("delattr"),
                            self.expr(t.value), t.attr])
            elif isinstance(t, ast.Name):
                out.append([Sym("py-del"), self.name(t.id)])
            else:
                raise Unsupported(f"del of {type(t).__name__}")
        return out[0] if len(out) == 1 else [Sym("progn"), *out]

    def s_With(self, node):
        if node.items and any(i.optional_vars is not None
                              and not isinstance(i.optional_vars, ast.Name)
                              for i in node.items):
            raise Unsupported("a with-target that is not a plain name")
        clauses = []
        for i in node.items:
            if i.optional_vars is None:
                clauses.append(self.expr(i.context_expr))
            else:
                clauses.append([self.name(i.optional_vars.id),
                                self.expr(i.context_expr)])
        return [Sym("py-with"), clauses, *self.body(node.body)]

    def s_Try(self, node):
        body = self.seq(node.body)
        if node.orelse:
            # the else clause runs only if the body raised nothing, and an
            # exception in it is *not* caught, so it cannot simply be appended
            flag = Sym("%no-error")
            body = [Sym("progn"), body, [Sym("setq"), flag, True]]
            after = [[Sym("when"), [Sym("py-truthy"), flag],
                      *self.body(node.orelse)]]
        else:
            after = []
        if node.handlers:
            form = [Sym("handler-case"), body]
            for h in node.handlers:
                kind = Sym("error") if h.type is None else self._exc_name(h.type)
                var = [self.name(h.name)] if h.name else [Sym("%e")]
                form.append([kind, var, *self.body(h.body)])
            body = form
        if after:
            body = [Sym("let"), [[Sym("%no-error"), False]], body, *after]
        if node.finalbody:
            body = [Sym("unwind-protect"), body, *self.body(node.finalbody)]
        return body

    def _exc_name(self, node):
        if isinstance(node, ast.Name):
            return self.name(node.id)
        if isinstance(node, ast.Attribute):
            return self.expr(node)
        if isinstance(node, ast.Tuple):
            return [self._exc_name(e) for e in node.elts]
        raise Unsupported(f"an except clause naming {type(node).__name__}")

    # -- definitions ------------------------------------------------------

    def _returning(self, body, tag, stmts):
        """Make the function's value Python's.

        A Common Lisp body returns its last form; a Python function that falls
        off the end returns None.  And a `return` in tail position needs no
        block exit, since the value of the last form is already the value.
        """
        if stmts and isinstance(stmts[-1], ast.Return):
            if body and isinstance(body[-1], list) \
                    and body[-1][:2] == [Sym("return-from"), tag]:
                body = body[:-1] + [body[-1][2]]
            return body
        return body + [Sym("py-none")]

    def _defaults(self, args):
        """Default expressions, which Python evaluates in the *enclosing*
        scope -- so they are translated before the new scope is pushed."""
        return ([self.expr(d) for d in args.defaults],
                [_NO_DEFAULT if d is None else self.expr(d)
                 for d in args.kw_defaults])

    def _lambda_list(self, args, defaults=None):
        """A Python signature as a lambda list.

        Python's *args is a tuple where Common Lisp's &rest is a list, and
        Python has keyword-only parameters that Common Lisp does not, so those
        get markers of their own -- &py-rest, &py-kwonly, &py-kwargs -- rather
        than being forced into the Lisp ones and quietly changing shape.
        """
        pos_d, kw_d = defaults if defaults is not None else self._defaults(args)
        out = []
        plain = list(args.posonlyargs) + list(args.args)
        required = len(plain) - len(pos_d)
        for a in plain[:required]:
            out.append(self.name(a.arg))
        if pos_d:
            out.append(Sym("&optional"))
            for a, d in zip(plain[required:], pos_d):
                out.append([self.name(a.arg), d])
        if args.vararg:
            out += [Sym("&py-rest"), self.name(args.vararg.arg)]
        if args.kwonlyargs:
            out.append(Sym("&py-kwonly"))
            for a, d in zip(args.kwonlyargs, kw_d):
                out.append(self.name(a.arg) if d is _NO_DEFAULT
                           else [self.name(a.arg), d])
        if args.kwarg:
            out += [Sym("&py-kwargs"), self.name(args.kwarg.arg)]
        return out

    def s_FunctionDef(self, node, head="defun"):
        name = self.name(node.name)
        decorators = [self.expr(d) for d in node.decorator_list]
        defaults = self._defaults(node.args)
        self.blocks.append(name)
        self.scopes.append(_scope_names(node.body, node))
        self.selves.append(self._first_param(node))
        try:
            params = self._lambda_list(node.args, defaults)
            body = self.body(node.body)
        finally:
            self.blocks.pop()
            self.scopes.pop()
            self.selves.pop()
        body = self._returning(body, name, node.body)
        if decorators:
            return [Sym("defun-decorated"), decorators, name, params, *body]
        return [Sym(head), name, params, *body]

    def _first_param(self, node):
        """The name a zero-argument super() needs as its second argument."""
        plain = list(node.args.posonlyargs) + list(node.args.args)
        return self.name(plain[0].arg) if plain else None

    def s_AsyncFunctionDef(self, node):
        if node.decorator_list:
            raise Unsupported("a decorated async def")
        return self.s_FunctionDef(node, head="defun-async")

    def s_ClassDef(self, node):
        """A class body is a scope, run top to bottom, where each statement can
        see what the ones before it bound -- a method, a constant, anything.
        So it is translated as an ordinary statement sequence inside a thunk
        that hands back its locals, which is what Python itself does."""
        self.scopes.append(_scope_names(node.body, node))
        self.classes.append(self.name(node.name))
        try:
            body = self.body(node.body)
        finally:
            self.scopes.pop()
            self.classes.pop()
        thunk = [Sym("lambda"), [], *body, [Sym("py-locals")]]
        bases = [Sym("list"), *[self.expr(b) for b in node.bases]]
        form = [Sym("py-class-body"), node.name, bases, thunk]
        for k in node.keywords:
            if k.arg is None:
                raise Unsupported("** in a class header")
            form += [Kw(k.arg), self.expr(k.value)]
        for d in reversed(node.decorator_list):
            form = [Sym("py-call"), self.expr(d), form]
        return [Sym("setq"), self.name(node.name), form]

    def _method(self, node):
        """A method as a lambda, for the value of a decorator expression."""
        tag = Sym("%ret")
        defaults = self._defaults(node.args)
        self.blocks.append(tag)
        self.scopes.append(_scope_names(node.body, node))
        self.selves.append(self._first_param(node))
        try:
            params = self._lambda_list(node.args, defaults)
            body = self.body(node.body)
        finally:
            self.blocks.pop()
            self.scopes.pop()
            self.selves.pop()
        body = self._returning(body, tag, node.body)
        inner = [Sym("lambda"), params, [Sym("block"), tag, *body]]
        for d in reversed(node.decorator_list):
            name = self._dotted(d) or getattr(d, "id", None)
            if name == "staticmethod":
                inner = [Sym("py-staticmethod"), inner]
            else:
                inner = [Sym("py-call"), self.expr(d), inner]
        return inner

    # -- imports ----------------------------------------------------------

    def s_Import(self, node):
        out = []
        for a in node.names:
            if a.asname:
                out.append([Sym("py-import-as"), Sym(a.name), Sym(a.asname)])
            else:
                out.append([Sym("py-import"), Sym(a.name)])
        return out[0] if len(out) == 1 else [Sym("progn"), *out]

    def s_ImportFrom(self, node):
        if node.level:
            raise Unsupported("a relative import")
        out = [[Sym("py-import"), Sym(node.module)]]
        for a in node.names:
            if a.name == "*":
                return [Sym("py-import-star"), Sym(node.module)]
            out.append([Sym("setq"), self.name(a.asname or a.name),
                        Sym(f"{node.module}.{a.name}")])
        return [Sym("progn"), *out]


def _shallow(stmts):
    """Statements in the same loop -- not those inside a nested loop or def."""
    for s in stmts:
        yield s
        if isinstance(s, (ast.For, ast.While, ast.FunctionDef,
                          ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        for field in ("body", "orelse", "finalbody"):
            yield from _shallow(getattr(s, field, []))
        for h in getattr(s, "handlers", []):
            yield from _shallow(h.body)


_PRELUDE = """;;;; Translated from Python by hyclb.frompy.
;;;;
;;;; Operators that Common Lisp and Python disagree on are written explicitly
;;;; as (py-binop ...), (py-truthy ...) and so on, so the behaviour is
;;;; Python's.  Where they agree the Lisp operator is used.

"""


def translate_source(source, filename="<string>"):
    """Return Common Lisp source, and the names that had to be renamed."""
    tree = ast.parse(source, filename)
    t = Translator(_scope_names(tree.body))
    forms = t.module(tree)
    out = [_PRELUDE.rstrip()]
    if t.name.used_builtins:
        out.append("\n(py-import builtins)")
    if t.name.renamed:
        out.append(";;;; Renamed, because hyclb already means something by the\n"
                   ";;;; original: "
                   + ", ".join(f"{k} -> {v}" for k, v in
                               sorted(t.name.renamed.items())))
    out.append("")
    for f in forms:
        out.append(render(f))
        out.append("")
    return "\n".join(out), dict(t.name.renamed)


def translate_file(path):
    with open(path) as f:
        return translate_source(f.read(), path)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    out = None
    if "-o" in argv:
        i = argv.index("-o")
        out = argv[i + 1]
        del argv[i:i + 2]
    if len(argv) != 1:
        sys.stderr.write("usage: python -m hyclb.frompy FILE.py [-o OUT.lisp]\n")
        return 2
    try:
        text, renamed = translate_file(argv[0])
    except Unsupported as e:
        sys.stderr.write(f"hyclb.frompy: cannot translate {e}\n")
        return 1
    if out:
        with open(out, "w") as f:
            f.write(text)
        if renamed:
            sys.stderr.write(f"hyclb.frompy: renamed {len(renamed)} name(s)\n")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
