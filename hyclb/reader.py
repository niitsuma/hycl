"""Parse the s-expressions SBCL prints back to us into runtime objects.

SBCL prints under a ``readtable-case :invert`` readtable, so a symbol whose
internal name is ``CAR`` arrives here spelled ``car`` -- already the identifier
we want on the Python side.  This reader therefore never case-folds.
"""

import re
from fractions import Fraction

from .runtime import NIL, T, Cons, Keyword, Symbol, from_iterable

_TERMINATORS = set('()"\'` \t\n\r;')
_INT = re.compile(r"^[+-]?\d+\.?$")
_RATIO = re.compile(r"^[+-]?\d+/\d+$")
_FLOAT = re.compile(
    r"^[+-]?(\d+\.\d*|\.\d+)([esfdlESFDL][+-]?\d+)?$|^[+-]?\d+[esfdlESFDL][+-]?\d+$"
)

_uninterned_counter = 0


class ReadError(Exception):
    pass


class Reader:
    def __init__(self, text):
        self.s = text
        self.i = 0

    # -- character level ---------------------------------------------------

    def _peek(self):
        return self.s[self.i] if self.i < len(self.s) else ""

    def _skip(self):
        while self.i < len(self.s):
            c = self.s[self.i]
            if c in " \t\n\r":
                self.i += 1
            elif c == ";":
                while self.i < len(self.s) and self.s[self.i] != "\n":
                    self.i += 1
            else:
                return

    # -- forms -------------------------------------------------------------

    def read(self):
        self._skip()
        if self.i >= len(self.s):
            raise ReadError("unexpected end of input")
        c = self.s[self.i]
        if c == "(":
            self.i += 1
            return self._read_list()
        if c == ")":
            raise ReadError("unbalanced close paren")
        if c == '"':
            self.i += 1
            return self._read_string()
        if c == "'":
            self.i += 1
            return from_iterable([Symbol("quote", "COMMON-LISP"), self.read()])
        if c == "#":
            return self._read_dispatch()
        if c == "|":
            self.i += 1
            return Symbol(self._read_bars())
        return self._read_atom()

    def read_all(self):
        out = []
        while True:
            self._skip()
            if self.i >= len(self.s):
                return out
            out.append(self.read())

    def _read_list(self):
        items = []
        tail = NIL
        while True:
            self._skip()
            if self.i >= len(self.s):
                raise ReadError("unexpected end of list")
            if self.s[self.i] == ")":
                self.i += 1
                return from_iterable(items, tail)
            start = self.i
            form = self.read()
            # a lone dot separates the tail of a dotted pair
            if (
                isinstance(form, Symbol)
                and form.name == "."
                and self.s[start:self.i].strip() == "."
            ):
                tail = self.read()
                self._skip()
                if self._peek() != ")":
                    raise ReadError("malformed dotted list")
                self.i += 1
                return from_iterable(items, tail)
            items.append(form)

    def _read_string(self):
        out = []
        while True:
            if self.i >= len(self.s):
                raise ReadError("unterminated string")
            c = self.s[self.i]
            self.i += 1
            if c == "\\":
                out.append(self.s[self.i])
                self.i += 1
            elif c == '"':
                return "".join(out)
            else:
                out.append(c)

    def _read_bars(self):
        out = []
        while True:
            if self.i >= len(self.s):
                raise ReadError("unterminated |symbol|")
            c = self.s[self.i]
            self.i += 1
            if c == "\\":
                out.append(self.s[self.i])
                self.i += 1
            elif c == "|":
                return "".join(out)
            else:
                out.append(c)

    def _read_dispatch(self):
        global _uninterned_counter
        self.i += 1  # consume '#'
        c = self._peek()
        if c == "\\":  # character literal
            self.i += 1
            start = self.i
            self.i += 1
            while self.i < len(self.s) and self.s[self.i] not in _TERMINATORS:
                self.i += 1
            tok = self.s[start:self.i]
            named = {"Space": " ", "Newline": "\n", "Tab": "\t", "Nul": "\0"}
            return named.get(tok, tok[0])
        if c == "(":  # simple vector
            self.i += 1
            return list(_iterate(self._read_list()))
        if c == ":":  # uninterned symbol; keep each occurrence distinct
            self.i += 1
            name = self._read_token()
            _uninterned_counter += 1
            return Symbol(f"{name}", f"#UNINTERNED-{_uninterned_counter}")
        if c == "'":  # #'fn
            self.i += 1
            return from_iterable([Symbol("function", "COMMON-LISP"), self.read()])
        raise ReadError(f"unsupported dispatch macro #{c}")

    def _read_token(self):
        start = self.i
        while self.i < len(self.s) and self.s[self.i] not in _TERMINATORS:
            if self.s[self.i] == "\\":
                self.i += 1
            self.i += 1
        return self.s[start:self.i]

    def _read_atom(self):
        tok = self._read_token()
        if not tok:
            raise ReadError(f"empty token at {self.i}")
        if _INT.match(tok):
            return int(tok.rstrip("."))
        if _RATIO.match(tok):
            f = Fraction(tok)
            return f.numerator if f.denominator == 1 else f
        if _FLOAT.match(tok):
            return float(tok.replace("d", "e").replace("D", "e").replace("f", "e").replace("F", "e"))
        return _symbol_from_token(tok)


def _iterate(x):
    while isinstance(x, Cons):
        yield x.car
        x = x.cdr


def _symbol_from_token(tok):
    if tok.startswith(":"):
        return Keyword(tok[1:])
    if "::" in tok:
        pkg, name = tok.split("::", 1)
        return Symbol(name, pkg)
    # a single colon is a package separator only when not at either end
    idx = tok.find(":")
    if 0 < idx < len(tok) - 1:
        return Symbol(tok[idx + 1 :], tok[:idx])
    if tok in ("nil", "NIL"):
        return NIL
    if tok in ("t", "T"):
        return T
    return Symbol(tok, "COMMON-LISP-USER")


def read(text):
    return Reader(text).read()


def read_all(text):
    return Reader(text).read_all()
