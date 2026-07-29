"""Common Lisp data types and core functions, hosted on Python.

Symbols are interned per package so that EQ is object identity.  NIL is a
symbol that doubles as the empty list, and it is the only false value --
Python falsiness is deliberately not used anywhere.
"""

from fractions import Fraction

# --------------------------------------------------------------------------
# symbols


class Symbol:
    __slots__ = ("name", "package", "plist")
    _table = {}

    def __new__(cls, name, package="COMMON-LISP-USER"):
        key = (package, name)
        got = cls._table.get(key)
        if got is None:
            got = object.__new__(cls)
            object.__setattr__(got, "name", name)
            object.__setattr__(got, "package", package)
            object.__setattr__(got, "plist", {})
            cls._table[key] = got
        return got

    def __repr__(self):
        if self.package in ("COMMON-LISP-USER", "COMMON-LISP"):
            return self.name
        return f"{self.package}::{self.name}"

    def __reduce__(self):
        return (Symbol, (self.name, self.package))


def intern(name, package="COMMON-LISP-USER"):
    return Symbol(name, package)


NIL = Symbol("NIL", "COMMON-LISP")
T = Symbol("T", "COMMON-LISP")


class Keyword(Symbol):
    __slots__ = ()

    def __new__(cls, name):
        return Symbol.__new__(cls, name, "KEYWORD")

    def __repr__(self):
        return ":" + self.name


# --------------------------------------------------------------------------
# conses


class Cons:
    __slots__ = ("car", "cdr")

    def __init__(self, car, cdr):
        self.car = car
        self.cdr = cdr

    def __iter__(self):
        """Iterate a proper list; a dotted tail is reported as an error."""
        node = self
        while isinstance(node, Cons):
            yield node.car
            node = node.cdr
        if node is not NIL:
            raise TypeError("iteration over an improper list")

    def __len__(self):
        return len(to_list(self))

    def __getitem__(self, i):
        return to_list(self)[i]

    def __repr__(self):
        out = []
        node = self
        while isinstance(node, Cons):
            out.append(repr(node.car))
            node = node.cdr
        if node is not NIL:
            out.append(".")
            out.append(repr(node))
        return "(" + " ".join(out) + ")"


def from_iterable(items, tail=NIL):
    acc = tail
    for x in reversed(list(items)):
        acc = Cons(x, acc)
    return acc


def to_list(x):
    out = []
    while isinstance(x, Cons):
        out.append(x.car)
        x = x.cdr
    return out


# --------------------------------------------------------------------------
# truth
#
# CL has exactly one false value.  Everything else -- 0, "", the empty
# Python list -- is true.  Nothing here consults Python's __bool__.


def truthy(x):
    """CL has one false value, NIL.

    Python's False is admitted as false too: it is what Python predicates
    return, and CL code has no other way to produce it.  0, "" and [] stay
    true, as CL requires.
    """
    return x is not NIL and x is not False


def boolify(x):
    return T if x else NIL


# --------------------------------------------------------------------------
# core functions.  Names are the CL names with a cl_ prefix; the translation
# layer emits `cl-car` etc., which Hy mangles to these.


# CAR and CDR also walk Python sequences, so DOLIST and friends iterate over
# whatever a Python library hands back.


def cl_car(x):
    if x is NIL:
        return NIL
    if isinstance(x, Cons):
        return x.car
    if isinstance(x, (list, tuple)):
        return x[0] if len(x) else NIL
    raise TypeError(f"CAR: not a list: {x!r}")


def cl_cdr(x):
    if x is NIL:
        return NIL
    if isinstance(x, Cons):
        return x.cdr
    if isinstance(x, (list, tuple)):
        return list(x[1:]) if len(x) > 1 else NIL
    raise TypeError(f"CDR: not a list: {x!r}")


def cl_cons(a, b):
    return Cons(a, b)


def cl_list(*xs):
    return from_iterable(xs)


def cl_list_star(*xs):
    if not xs:
        return NIL
    return from_iterable(xs[:-1], xs[-1])


def cl_null(x):
    return T if x is NIL else NIL


cl_not = cl_null


def cl_consp(x):
    return boolify(isinstance(x, Cons))


def cl_atom(x):
    return boolify(not isinstance(x, Cons))


def cl_listp(x):
    return boolify(isinstance(x, Cons) or x is NIL)


def cl_symbolp(x):
    return boolify(isinstance(x, Symbol))


def cl_eq(a, b):
    return boolify(a is b)


def cl_eql(a, b):
    a, b = _canon(a), _canon(b)
    if a is b:
        return T
    if isinstance(a, (int, float, Fraction, complex)) and isinstance(
        b, (int, float, Fraction, complex)
    ):
        return boolify(type(a) is type(b) and a == b)
    return NIL


def cl_equal(a, b):
    if truthy(cl_eql(a, b)):
        return T
    if isinstance(a, Cons) and isinstance(b, Cons):
        return boolify(truthy(cl_equal(a.car, b.car)) and truthy(cl_equal(a.cdr, b.cdr)))
    if isinstance(a, str) and isinstance(b, str):
        return boolify(a == b)
    return NIL


def cl_rplaca(c, v):
    c.car = v
    return c


def cl_rplacd(c, v):
    c.cdr = v
    return c


def cl_length(x):
    if x is NIL:
        return 0
    if isinstance(x, Cons):
        return len(to_list(x))
    return len(x)


def cl_append(*ls):
    if not ls:
        return NIL
    acc = ls[-1]
    for l in reversed(ls[:-1]):
        acc = from_iterable(to_list(l), acc)
    return acc


def cl_reverse(l):
    return from_iterable(reversed(to_list(l)))


def cl_nth(n, l):
    items = to_list(l)
    return items[n] if n < len(items) else NIL


def cl_elt(seq, n):
    return to_list(seq)[n] if isinstance(seq, Cons) else seq[n]


def cl_funcall(f, *args):
    return f(*args)


def cl_apply(f, *args):
    if not args:
        return f()
    tail = args[-1]
    spread = to_list(tail) if isinstance(tail, Cons) else ([] if tail is NIL else list(tail))
    return f(*(list(args[:-1]) + spread))


def cl_values(*vs):
    """Primary value is returned; the rest are stashed for MULTIPLE-VALUE-BIND."""
    global _extra_values
    _extra_values = list(vs[1:])
    return vs[0] if vs else NIL


_extra_values = []


def cl_extra_values():
    return _extra_values


def cl_print(x):
    print(_write_to_string(x))
    return x


def _write_to_string(x):
    if x is NIL:
        return "NIL"
    if x is T:
        return "T"
    if isinstance(x, bool):
        return "T" if x else "NIL"
    if isinstance(x, str):
        return '"' + x.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return repr(x)


def cl_error(designator, *args):
    raise cl_make_condition(designator, *args)


# arithmetic that CL defines differently from Python


def cl_div(*args):
    """CL / is exact: (/ 1 3) is the rational 1/3, not 0.333..."""
    if len(args) == 1:
        args = (1,) + args
    acc = args[0]
    for x in args[1:]:
        if isinstance(acc, int) and isinstance(x, int):
            acc = Fraction(acc, x)
        else:
            acc = acc / x
        if isinstance(acc, Fraction) and acc.denominator == 1:
            acc = acc.numerator
    return acc


def cl_1plus(x):
    return x + 1


def cl_1minus(x):
    return x - 1


# --------------------------------------------------------------------------
# support for the special-operator macros in cl.hy


class BlockExit(Exception):
    """Non-local exit for BLOCK / RETURN-FROM."""

    def __init__(self, name, value):
        super().__init__(name)
        self.name = name
        self.value = value


def cl_symbol(name, package="COMMON-LISP-USER"):
    return Symbol(name, package)


def cl_keyword(name):
    return Keyword(name)


# --------------------------------------------------------------------------
# Common Lisp keyword arguments
#
# A CL call passes :test and its value as two ordinary arguments; Python wants
# a keyword.  Functions that accept keywords are wrapped so the two agree.


def cl_keywords(fn):
    def wrapper(*args):
        pos, kw = [], {}
        i = 0
        while i < len(args):
            if isinstance(args[i], Keyword) and i + 1 < len(args):
                kw[args[i].name.lower().replace("-", "_")] = args[i + 1]
                i += 2
            else:
                pos.append(args[i])
                i += 1
        return fn(*pos, **kw)

    wrapper.__name__ = getattr(fn, "__name__", "wrapped")
    return wrapper


def _same(test, key):
    """The comparison a :test/:key pair asks for."""
    pick = (lambda x: key(x)) if key is not None else (lambda x: x)
    if test is None:
        return lambda a, b: truthy(cl_eql(a, pick(b)))
    return lambda a, b: truthy(test(a, pick(b)))


@cl_keywords
def cl_member(item, l, test=None, key=None):
    same = _same(test, key)
    node = l
    while isinstance(node, Cons):
        if same(item, node.car):
            return node
        node = node.cdr
    return NIL


@cl_keywords
def cl_assoc(item, alist, test=None, key=None):
    same = _same(test, key)
    for pair in _seq(alist):
        if isinstance(pair, Cons) and same(item, pair.car):
            return pair
    return NIL


@cl_keywords
def cl_remove(item, l, test=None, key=None):
    same = _same(test, key)
    return _reseq([x for x in _seq(l) if not same(item, x)], l)


@cl_keywords
def cl_find(item, l, test=None, key=None):
    same = _same(test, key)
    for x in _seq(l):
        if same(item, x):
            return x
    return NIL


@cl_keywords
def cl_position(item, l, test=None, key=None):
    same = _same(test, key)
    for i, x in enumerate(_seq(l)):
        if same(item, x):
            return i
    return NIL


@cl_keywords
def cl_count(item, l, test=None, key=None):
    same = _same(test, key)
    return sum(1 for x in _seq(l) if same(item, x))


# numeric predicates return CL booleans, not Python ones


def _chain(op, args):
    return boolify(all(op(args[i], args[i + 1]) for i in range(len(args) - 1)))


def cl_numeq(*a):
    return _chain(lambda x, y: x == y, a)


def cl_numne(*a):
    return boolify(len(set(a)) == len(a))


def cl_lt(*a):
    return _chain(lambda x, y: x < y, a)


def cl_gt(*a):
    return _chain(lambda x, y: x > y, a)


def cl_le(*a):
    return _chain(lambda x, y: x <= y, a)


def cl_ge(*a):
    return _chain(lambda x, y: x >= y, a)


# --------------------------------------------------------------------------
# more of the standard library


def cl_endp(x):
    return T if x is NIL or (isinstance(x, (list, tuple)) and not x) else NIL


def cl_mod(a, b):
    return a % b


def cl_rem(a, b):
    r = abs(a) % abs(b)
    return r if a >= 0 else -r


def cl_zerop(x):
    return boolify(x == 0)


def cl_plusp(x):
    return boolify(x > 0)


def cl_minusp(x):
    return boolify(x < 0)


def cl_oddp(x):
    return boolify(x % 2 != 0)


def cl_evenp(x):
    return boolify(x % 2 == 0)


def cl_numberp(x):
    return boolify(isinstance(x, (int, float, complex, Fraction)))


def cl_stringp(x):
    return boolify(isinstance(x, str) and not isinstance(x, Symbol))


def cl_functionp(x):
    return boolify(callable(x))


def cl_mapcar(f, *ls):
    return from_iterable([f(*xs) for xs in zip(*[to_list(l) for l in ls])])


def cl_mapc(f, *ls):
    for xs in zip(*[to_list(l) for l in ls]):
        f(*xs)
    return ls[0] if ls else NIL








def cl_first(l):
    return cl_car(l)


def cl_second(l):
    return cl_car(cl_cdr(l))


def cl_third(l):
    return cl_car(cl_cdr(cl_cdr(l)))


def cl_cadr(l):
    return cl_car(cl_cdr(l))


def cl_caar(l):
    return cl_car(cl_car(l))


def cl_cddr(l):
    return cl_cdr(cl_cdr(l))


def cl_caddr(l):
    return cl_car(cl_cddr(l))


def cl_last(l):
    node = l
    while isinstance(node, Cons) and isinstance(node.cdr, Cons):
        node = node.cdr
    return node


def cl_butlast(l):
    items = to_list(l)
    return from_iterable(items[:-1])


def cl_nthcdr(n, l):
    for _ in range(n):
        l = cl_cdr(l)
    return l


_gensym_counter = 0


def cl_gensym(prefix="G"):
    global _gensym_counter
    _gensym_counter += 1
    return Symbol(f"{prefix}{_gensym_counter}", "#GENSYM")


def cl_string_eq(a, b):
    return boolify(str(a) == str(b))


# --------------------------------------------------------------------------
# Python interoperation
#
# Python objects are ordinary values here: they live in Lisp variables, get
# passed to Lisp functions and are returned unchanged.  Only the two list
# representations need converting, and only at the boundary.


def to_py(x):
    """Lisp value -> Python value.  Anything not a list is already Python."""
    if x is NIL:
        return []
    if x is T:
        return True
    if isinstance(x, Cons):
        return [to_py(e) for e in to_list(x)]
    return x


def from_py(x):
    """Python value -> Lisp value."""
    if x is None:
        return NIL
    if x is True:
        return T
    if x is False:
        return NIL
    if isinstance(x, (list, tuple)):
        return from_iterable([from_py(e) for e in x])
    return x


def cl_py_call(f, *args):
    """Call a Python callable.

    Trailing `:keyword value` pairs become keyword arguments, so a Lisp call
    reads the way a Python one does.  Lisp lists are converted on the way in;
    the result comes back as-is, because a Python object is a perfectly good
    Lisp value.
    """
    pos, kw = [], {}
    i = 0
    while i < len(args):
        a = args[i]
        if isinstance(a, Keyword) and i + 1 < len(args):
            kw[a.name] = to_py(args[i + 1])
            i += 2
        else:
            pos.append(to_py(a))
            i += 1
    return f(*pos, **kw)


def cl_py_attr(obj, name):
    return getattr(obj, str(name))


def cl_py_set_attr(obj, name, value):
    setattr(obj, str(name), value)
    return value


def cl_py_method(obj, name, *args):
    return cl_py_call(getattr(obj, str(name)), *args)


def cl_py_getitem(obj, key):
    return obj[to_py(key)]


def cl_py_setitem(obj, key, value):
    obj[to_py(key)] = value
    return value


def cl_py_list(x):
    v = to_py(x)
    return v if isinstance(v, list) else list(v)


def cl_py_tuple(x):
    return tuple(to_py(x))


py_true = True
py_false = False
py_none = None


def cl_py_class(name, bases, *kv):
    """Build a Python class whose methods are Lisp functions.

    Subclassing a Python base from Lisp needs no new syntax: the methods are
    ordinary closures and `type` does the rest.
    """
    ns = {}
    i = 0
    while i < len(kv):
        key, fn = str(kv[i]), kv[i + 1]
        # every Lisp form has a value, but Python insists __init__ has none
        ns[key] = _void(fn) if key == "__init__" else fn
        i += 2
    base_list = to_list(bases) if isinstance(bases, Cons) else list(bases)
    return type(str(name), tuple(base_list), ns)


def _void(fn):
    def wrapper(*args, **kw):
        fn(*args, **kw)

    return wrapper


# `(+ a b)` compiles to Python's operator, but `#'+` needs a function object


def cl_plus(*a):
    acc = 0
    for x in a:
        acc = acc + x
    return acc


def cl_minus(*a):
    if not a:
        return 0
    if len(a) == 1:
        return -a[0]
    acc = a[0]
    for x in a[1:]:
        acc = acc - x
    return acc


def cl_times(*a):
    acc = 1
    for x in a:
        acc = acc * x
    return acc


# --------------------------------------------------------------------------
# a wider slice of the standard library, added as library expansions asked
# for it


def cl_identity(x):
    return x


def cl_abs(x):
    return abs(x)


def cl_min(*a):
    return min(a)


def cl_max(*a):
    return max(a)


def _canon(x):
    """Common Lisp keeps rationals canonical: 2/1 is the integer 2."""
    return x.numerator if isinstance(x, Fraction) and x.denominator == 1 else x


def cl_expt(b, e):
    # a negative integer power of an integer is a rational in CL, not a float
    if isinstance(b, int) and isinstance(e, int) and e < 0:
        return _canon(Fraction(1, b ** -e))
    return _canon(b ** e)


def cl_sqrt(x):
    return x ** 0.5


def cl_floor(x, d=1):
    import math

    return math.floor(x / d)


def cl_ceiling(x, d=1):
    import math

    return math.ceil(x / d)


def cl_truncate(x, d=1):
    return int(x / d)


def cl_round(x, d=1):
    return round(x / d)


def cl_char_eq(a, b):
    return boolify(a == b)


def cl_symbol_name(s):
    return s.name


def cl_string(x):
    return x.name if isinstance(x, Symbol) else str(x)


def cl_string_upcase(s):
    return str(s).upper()


def cl_string_downcase(s):
    return str(s).lower()


def _seq(x):
    return to_list(x) if isinstance(x, Cons) else ([] if x is NIL else list(x))


def _reseq(items, model):
    return from_iterable(items) if isinstance(model, (Cons,)) or model is NIL else type(model)(items)


def cl_subseq(s, start, end=None):
    return _reseq(_seq(s)[start:end], s)


def cl_concatenate(kind, *seqs):
    items = [x for s in seqs for x in _seq(s)]
    name = str(kind).lower()
    if name == "string":
        return "".join(items)
    return from_iterable(items)








@cl_keywords
def cl_find_if(pred, s, **kw):
    for x in _seq(s):
        if truthy(pred(x)):
            return x
    return NIL


@cl_keywords
def cl_position_if(pred, s, **kw):
    for i, x in enumerate(_seq(s)):
        if truthy(pred(x)):
            return i
    return NIL


@cl_keywords
def cl_count_if(pred, s, **kw):
    return sum(1 for x in _seq(s) if truthy(pred(x)))


@cl_keywords
def cl_remove_if(pred, s, **kw):
    return _reseq([x for x in _seq(s) if not truthy(pred(x))], s)


@cl_keywords
def cl_remove_if_not(pred, s, **kw):
    return _reseq([x for x in _seq(s) if truthy(pred(x))], s)


def cl_every(pred, *seqs):
    return boolify(all(truthy(pred(*xs)) for xs in zip(*[_seq(s) for s in seqs])))


def cl_some(pred, *seqs):
    for xs in zip(*[_seq(s) for s in seqs]):
        v = pred(*xs)
        if truthy(v):
            return v
    return NIL


def cl_notany(pred, *seqs):
    return cl_not(cl_some(pred, *seqs))


@cl_keywords
def cl_reduce(f, s, **kw):
    items = _seq(s)
    if "initial_value" in kw:
        acc = kw["initial_value"]
    elif items:
        acc, items = items[0], items[1:]
    else:
        return f()
    for x in items:
        acc = f(acc, x)
    return acc


@cl_keywords
def cl_sort(s, pred, **kw):
    import functools

    items = sorted(
        _seq(s), key=functools.cmp_to_key(lambda a, b: -1 if truthy(pred(a, b)) else 1)
    )
    return _reseq(items, s)


def cl_copy_list(l):
    return from_iterable(to_list(l))


def cl_nreverse(l):
    return cl_reverse(l)


def cl_nconc(*ls):
    return cl_append(*ls)


def cl_mapcan(f, *ls):
    out = []
    for xs in zip(*[_seq(l) for l in ls]):
        out.extend(_seq(f(*xs)))
    return from_iterable(out)


def cl_getf(plist, key, default=NIL):
    items = to_list(plist)
    for i in range(0, len(items) - 1, 2):
        if items[i] is key:
            return items[i + 1]
    return default


@cl_keywords
def cl_make_hash_table(**kw):
    return {}


def cl_gethash(key, table, default=NIL):
    got = table.get(_hashable(key), _MISSING)
    return default if got is _MISSING else got


_MISSING = object()


def cl_puthash(key, table, value):
    table[_hashable(key)] = value
    return value


def cl_remhash(key, table):
    return boolify(table.pop(_hashable(key), _MISSING) is not _MISSING)


def cl_hash_table_count(table):
    return len(table)


def _hashable(k):
    return tuple(to_list(k)) if isinstance(k, Cons) else k


def cl_format(dest, control, *args):
    """A subset: ~a ~s ~d ~% ~~ and the iteration ~{ ... ~^ ... ~}."""
    text = str(control)
    if "~{" in text:
        return _format_iteration(dest, text, args)
    out, i, ai = [], 0, 0
    text = str(control)
    while i < len(text):
        c = text[i]
        if c == "~" and i + 1 < len(text):
            d = text[i + 1].lower()
            i += 2
            if d == "%":
                out.append("\n")
            elif d == "~":
                out.append("~")
            elif d in "asd":
                out.append(_write_to_string(args[ai]) if d == "s" else _princ(args[ai]))
                ai += 1
            else:
                out.append("~" + d)
        else:
            out.append(c)
            i += 1
    s = "".join(out)
    if dest is NIL:
        return s
    print(s, end="")
    return NIL


def _princ(x):
    if x is NIL:
        return "NIL"
    if isinstance(x, Symbol):
        return x.name
    if isinstance(x, str):
        return x
    return _write_to_string(x)


def cl_princ(x):
    print(_princ(x), end="")
    return x


def cl_terpri():
    print()
    return NIL


# SBCL's internal setters, unlike RPLACD, return the new value rather than the
# cons -- they are what (setf (cdr x) v) expands into.


def cl_setcdr(c, v):
    c.cdr = v
    return v


def cl_setcar(c, v):
    c.car = v
    return v


# --------------------------------------------------------------------------
# DEFSTRUCT
#
# Structures become plain Python classes, so a struct instance can be handed
# to Python code and printed, pickled or stored like any other object.


def cl_struct_class(name, slots, defaults):
    slots = [str(s) for s in slots]

    def __init__(self, **kw):
        for slot, default in zip(slots, defaults):
            setattr(self, slot, kw.get(slot, default))

    def __repr__(self):
        body = " ".join(f":{s} {getattr(self, s)!r}" for s in slots)
        return f"#S({name} {body})"

    def __eq__(self, other):
        return type(other) is type(self) and all(
            getattr(self, s) == getattr(other, s) for s in slots
        )

    return type(
        str(name),
        (object,),
        {
            "__init__": __init__,
            "__repr__": __repr__,
            "__eq__": __eq__,
            "_slots": slots,
        },
    )


def cl_make_struct(cls, *args):
    kw = {}
    i = 0
    while i < len(args):
        if isinstance(args[i], Keyword) and i + 1 < len(args):
            kw[args[i].name] = args[i + 1]
            i += 2
        else:
            i += 1
    return cls(**kw)


def cl_struct_p(obj, cls):
    return boolify(isinstance(obj, cls))


def cl_slot(obj, name):
    return getattr(obj, str(name))


def cl_set_slot(obj, name, value):
    setattr(obj, str(name), value)
    return value


def cl_copy_struct(obj):
    new = object.__new__(type(obj))
    for s in type(obj)._slots:
        setattr(new, s, getattr(obj, s))
    return new


# --------------------------------------------------------------------------
# CLOS
#
# Classes are Python classes, so instances interoperate.  Generic functions
# are not: Python dispatches on the first argument only, so the method table
# is kept here and dispatch ranks candidates by total MRO distance.


class GenericFunction:
    def __init__(self, name):
        self.name = str(name)
        self.methods = []  # (specializers, qualifier, function)

    def add(self, specializers, qualifier, fn):
        key = (tuple(specializers), qualifier)
        self.methods = [m for m in self.methods if (tuple(m[0]), m[1]) != key]
        self.methods.append((list(specializers), qualifier, fn))

    def applicable(self, args):
        out = []
        for specs, qual, fn in self.methods:
            if len(specs) > len(args):
                continue
            distance = 0
            for spec, arg in zip(specs, args):
                if spec is None:
                    continue
                mro = type(arg).__mro__
                if spec not in mro:
                    break
                distance += mro.index(spec)
            else:
                out.append((distance, qual, fn))
        out.sort(key=lambda t: t[0])
        return out

    def __call__(self, *args):
        candidates = self.applicable(args)
        primaries = [fn for _, q, fn in candidates if q is None]
        if not primaries:
            raise TypeError(f"no applicable method for {self.name} on {args!r}")
        befores = [fn for _, q, fn in candidates if q == "before"]
        afters = [fn for _, q, fn in candidates if q == "after"]
        for fn in befores:
            fn(*args)
        result = _call_with_next(primaries, args)
        for fn in reversed(afters):
            fn(*args)
        return result


def _call_with_next(chain, args):
    """Run the most specific primary, with CALL-NEXT-METHOD available."""
    if not chain:
        raise TypeError("no next method")
    saved = _next_methods.get(id(chain[0]))
    _next_methods[id(chain[0])] = (chain[1:], args)
    try:
        return chain[0](*args)
    finally:
        if saved is None:
            _next_methods.pop(id(chain[0]), None)
        else:
            _next_methods[id(chain[0])] = saved


_next_methods = {}
_generics = {}


def cl_generic(name):
    got = _generics.get(str(name))
    if got is None:
        got = _generics[str(name)] = GenericFunction(name)
    return got


def cl_add_method(gf, specializers, qualifier, fn):
    gf.add(
        [None if s is NIL else s for s in to_list(specializers)],
        None if qualifier is NIL else str(qualifier),
        fn,
    )
    return gf


def cl_defclass(name, bases, slots):
    """SLOTS is a list of (name initform type) triples; the type may be NIL."""
    pairs, annotations = [], {}
    for spec in to_list(slots):
        parts = to_list(spec)
        slot = str(parts[0])
        pairs.append((slot, parts[1] if len(parts) > 1 else NIL))
        declared = parts[2] if len(parts) > 2 else NIL
        if declared is not NIL:
            py = cl_python_type(declared)
            if py is not None:
                annotations[slot] = py
    base_list = tuple(to_list(bases)) or (object,)

    def __init__(self, **kw):
        # inherited slots are initialised too, base classes first
        for klass in reversed(type(self).__mro__):
            for slot, default in getattr(klass, "_slot_pairs", ()):
                setattr(self, slot, kw.get(slot, default))

    def __repr__(self):
        return f"#<{name} {' '.join(str(s) for s, _ in pairs)}>"

    ns = {
        "__init__": __init__,
        "__repr__": __repr__,
        "_slot_pairs": pairs,
        "_slots": [s for s, _ in pairs],
        "__annotations__": annotations,
    }
    return type(str(name), base_list, ns)


def cl_make_instance(designator, *args):
    """MAKE-INSTANCE names its class with a symbol, as CL does."""
    cls = _classes[designator.name] if isinstance(designator, Symbol) else designator
    return cl_make_struct(cls, *args)


def cl_slot_value(obj, name):
    return getattr(obj, str(name))


def cl_set_slot_value(obj, name, value):
    setattr(obj, str(name), value)
    return value


def cl_find_class(name):
    return _classes[str(name)]


_classes = {}


def cl_register_class(name, cls):
    _classes[str(name)] = cls
    return cls


# the macro cl-defclass mangles to the same Python name, so the class builder
# is reached under a distinct one
cl_defclass_impl = cl_defclass


# --------------------------------------------------------------------------
# conditions
#
# Conditions are Python exceptions, so HANDLER-CASE catches what Python code
# raises and Python catches what Lisp signals.


class Condition(Exception):
    _slot_pairs = ()

    def __init__(self, **kw):
        for klass in reversed(type(self).__mro__):
            for slot, default in getattr(klass, "_slot_pairs", ()):
                setattr(self, slot, kw.get(slot, default))
        Exception.__init__(self, type(self).__name__)


class SimpleError(Condition):
    _slot_pairs = (("format_control", ""), ("format_arguments", NIL))

    def __str__(self):
        return cl_format(NIL, self.format_control, *to_list(self.format_arguments))


_conditions = {
    "condition": Exception,
    "error": Exception,
    "serious-condition": Exception,
    "simple-error": SimpleError,
    "type-error": TypeError,
    "arithmetic-error": ArithmeticError,
    "division-by-zero": ZeroDivisionError,
    "file-error": OSError,
    "end-of-file": EOFError,
    "unbound-variable": NameError,
}


def cl_condition_class(name):
    key = str(name)
    got = _conditions.get(key)
    if got is None:
        raise TypeError(f"unknown condition type: {key}")
    return got


def cl_define_condition(name, supers, slots):
    resolved = [cl_condition_class(s) for s in to_list(supers)]
    # (define-condition x (error) ...) names Python's Exception as the parent,
    # which carries no slots; splice in the slot-bearing base
    if not any(issubclass(p, Condition) for p in resolved):
        resolved = [Condition] + [p for p in resolved if not issubclass(Condition, p)]
    parents = tuple(resolved) or (Condition,)
    pairs = [
        (str(s.car), s.cdr.car if isinstance(s.cdr, Cons) else NIL)
        for s in to_list(slots)
    ]
    cls = type(str(name), parents, {"_slot_pairs": pairs})
    _conditions[str(name)] = cls
    return cls


def cl_make_condition(designator, *args):
    if isinstance(designator, Symbol):
        cls = cl_condition_class(designator.name)
        kw = {}
        i = 0
        while i < len(args):
            if isinstance(args[i], Keyword) and i + 1 < len(args):
                kw[args[i].name] = args[i + 1]
                i += 2
            else:
                i += 1
        return cls(**kw) if issubclass(cls, Condition) else cls(str(designator))
    return SimpleError(
        format_control=str(designator), format_arguments=from_iterable(args)
    )


def cl_signal(designator, *args):
    raise cl_make_condition(designator, *args)


# -- restarts


class RestartInvoke(Exception):
    def __init__(self, name, args):
        super().__init__(name)
        self.name = str(name)
        self.args = args


_restarts = []


def cl_push_restarts(names):
    _restarts.append([str(n) for n in names])
    return len(_restarts)


def cl_pop_restarts():
    if _restarts:
        _restarts.pop()
    return NIL


def cl_invoke_restart(name, *args):
    for frame in reversed(_restarts):
        if str(name) in frame:
            raise RestartInvoke(name, args)
    raise TypeError(f"no restart named {name}")


def cl_find_restart(name):
    for frame in reversed(_restarts):
        if str(name) in frame:
            return Symbol(str(name))
    return NIL


# the macro cl-define-condition mangles to the same name as the builder
cl_define_condition_impl = cl_define_condition


# --------------------------------------------------------------------------
# elementary functions, needed once a symbolic algebra system starts handing
# back derivatives


def _elementary(name):
    """An elementary function that defers to the object when it defines one.

    A Torch tensor knows how to take its own sine; `math.sin` does not know
    how to take a tensor's.
    """
    import math

    scalar = getattr(math, name)

    def fn(x):
        method = getattr(x, name, None)
        if method is not None and not isinstance(x, (int, float, complex)):
            return method()
        return scalar(x)

    fn.__name__ = "cl_" + name
    return fn


cl_sin = _elementary("sin")
cl_cos = _elementary("cos")
cl_tan = _elementary("tan")
cl_exp = _elementary("exp")


def cl_log(x, base=None):
    import math

    if base is not None:
        return math.log(x, base)
    method = getattr(x, "log", None)
    if method is not None and not isinstance(x, (int, float, complex)):
        return method()
    return math.log(x)


def py_staticmethod(f):
    return staticmethod(f)


# --------------------------------------------------------------------------
# Common Lisp type specifiers as Python annotations
#
# CL already has a way to state a type -- DECLARE and the :type slot option --
# and SBCL already reads it, so no new syntax is needed for annotations.

CL_TYPE_MAP = {
    "integer": int, "fixnum": int, "bignum": int, "unsigned-byte": int,
    "signed-byte": int, "bit": int,
    "float": float, "single-float": float, "double-float": float,
    "short-float": float, "long-float": float, "real": float,
    "rational": float, "ratio": float,
    "string": str, "simple-string": str, "base-string": str, "character": str,
    "boolean": bool,
    "list": list, "cons": list, "vector": list, "simple-vector": list,
    "array": list, "sequence": list,
    "hash-table": dict,
    "complex": complex,
}


def cl_python_type(name):
    return CL_TYPE_MAP.get(str(name))


# the c[ad]+r family, generated rather than written out


def cl_caar(x):
    return cl_car(cl_car(x))


def cl_cadr(x):
    return cl_car(cl_cdr(x))


def cl_cdar(x):
    return cl_cdr(cl_car(x))


def cl_cddr(x):
    return cl_cdr(cl_cdr(x))


def cl_caaar(x):
    return cl_car(cl_car(cl_car(x)))


def cl_caadr(x):
    return cl_car(cl_car(cl_cdr(x)))


def cl_cadar(x):
    return cl_car(cl_cdr(cl_car(x)))


def cl_caddr(x):
    return cl_car(cl_cdr(cl_cdr(x)))


def cl_cdaar(x):
    return cl_cdr(cl_car(cl_car(x)))


def cl_cdadr(x):
    return cl_cdr(cl_car(cl_cdr(x)))


def cl_cddar(x):
    return cl_cdr(cl_cdr(cl_car(x)))


def cl_cdddr(x):
    return cl_cdr(cl_cdr(cl_cdr(x)))


def cl_caaaar(x):
    return cl_car(cl_car(cl_car(cl_car(x))))


def cl_caaadr(x):
    return cl_car(cl_car(cl_car(cl_cdr(x))))


def cl_caadar(x):
    return cl_car(cl_car(cl_cdr(cl_car(x))))


def cl_caaddr(x):
    return cl_car(cl_car(cl_cdr(cl_cdr(x))))


def cl_cadaar(x):
    return cl_car(cl_cdr(cl_car(cl_car(x))))


def cl_cadadr(x):
    return cl_car(cl_cdr(cl_car(cl_cdr(x))))


def cl_caddar(x):
    return cl_car(cl_cdr(cl_cdr(cl_car(x))))


def cl_cadddr(x):
    return cl_car(cl_cdr(cl_cdr(cl_cdr(x))))


def cl_cdaaar(x):
    return cl_cdr(cl_car(cl_car(cl_car(x))))


def cl_cdaadr(x):
    return cl_cdr(cl_car(cl_car(cl_cdr(x))))


def cl_cdadar(x):
    return cl_cdr(cl_car(cl_cdr(cl_car(x))))


def cl_cdaddr(x):
    return cl_cdr(cl_car(cl_cdr(cl_cdr(x))))


def cl_cddaar(x):
    return cl_cdr(cl_cdr(cl_car(cl_car(x))))


def cl_cddadr(x):
    return cl_cdr(cl_cdr(cl_car(cl_cdr(x))))


def cl_cdddar(x):
    return cl_cdr(cl_cdr(cl_cdr(cl_car(x))))


def cl_cddddr(x):
    return cl_cdr(cl_cdr(cl_cdr(cl_cdr(x))))


# vectors, and the few remaining odds and ends a real library reaches for


def cl_vector(*xs):
    return list(xs)


def cl_aref(v, *indices):
    for i in indices:
        v = v[i]
    return v


def cl_svref(v, i):
    return v[i]


def cl_make_array(size, **kw):
    initial = kw.get("initial_element", NIL)
    n = size if isinstance(size, int) else to_list(size)[0]
    return [initial] * n


def cl_length_vector(v):
    return len(v)


def cl_null_p(x):
    return cl_null(x)


def cl_atom_p(x):
    return cl_atom(x)


def cl_vectorp(x):
    return boolify(isinstance(x, (list, tuple)))


def cl_arrayp(x):
    return boolify(isinstance(x, (list, tuple)))


def cl_simple_vector_p(x):
    return boolify(isinstance(x, (list, tuple)))


def cl_characterp(x):
    return boolify(isinstance(x, str) and len(x) == 1 and not isinstance(x, Symbol))


def cl_integerp(x):
    return boolify(isinstance(x, int) and not isinstance(x, bool))


def cl_floatp(x):
    return boolify(isinstance(x, float))


def cl_keywordp(x):
    return boolify(isinstance(x, Keyword))


def cl_equalp(a, b):
    if truthy(cl_equal(a, b)):
        return T
    if isinstance(a, str) and isinstance(b, str):
        return boolify(a.lower() == b.lower())
    if isinstance(a, (int, float, Fraction)) and isinstance(b, (int, float, Fraction)):
        return boolify(a == b)
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return boolify(len(a) == len(b)
                       and all(truthy(cl_equalp(x, y)) for x, y in zip(a, b)))
    return NIL


def cl_notevery(pred, *seqs):
    return cl_not(cl_every(pred, *seqs))


def cl_second_value(x):
    return x


@cl_keywords
def cl_remove_duplicates(l, test=None, key=None, from_end=NIL):
    same = _same(test, key)
    out = []
    for x in _seq(l):
        if not any(same(x, y) for y in out):
            out.append(x)
    return _reseq(out, l)


@cl_keywords
def cl_set_difference(a, b, test=None, key=None):
    same = _same(test, key)
    return from_iterable([x for x in _seq(a) if not any(same(x, y) for y in _seq(b))])


@cl_keywords
def cl_union(a, b, test=None, key=None):
    same = _same(test, key)
    out = list(_seq(a))
    for x in _seq(b):
        if not any(same(x, y) for y in out):
            out.append(x)
    return from_iterable(out)


@cl_keywords
def cl_intersection(a, b, test=None, key=None):
    same = _same(test, key)
    return from_iterable([x for x in _seq(a) if any(same(x, y) for y in _seq(b))])


def cl_typep(x, spec):
    """TYPEP over the type names the runtime knows about."""
    name = spec.name if isinstance(spec, Symbol) else str(spec)
    checks = {
        "symbol": lambda v: isinstance(v, Symbol),
        "number": lambda v: isinstance(v, (int, float, complex, Fraction))
        and not isinstance(v, bool),
        "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
        "float": lambda v: isinstance(v, float),
        "string": lambda v: isinstance(v, str) and not isinstance(v, Symbol),
        "list": lambda v: isinstance(v, Cons) or v is NIL,
        "cons": lambda v: isinstance(v, Cons),
        "null": lambda v: v is NIL,
        "atom": lambda v: not isinstance(v, Cons),
        "vector": lambda v: isinstance(v, (list, tuple)),
        "function": callable,
        "hash-table": lambda v: isinstance(v, dict),
        "t": lambda v: True,
    }
    check = checks.get(name.lower())
    return boolify(check(x)) if check else NIL


def cl_map(result_type, fn, *seqs):
    """CL's MAP takes the result type first; Python's map does not exist here."""
    out = [fn(*xs) for xs in zip(*[_seq(s) for s in seqs])]
    name = result_type.name.lower() if isinstance(result_type, Symbol) else str(result_type)
    if name == "list":
        return from_iterable(out)
    if name == "string":
        return "".join(out)
    if name in ("vector", "simple-vector", "array"):
        return out
    return NIL


def cl_mapl(fn, *ls):
    nodes = list(ls)
    while all(isinstance(n, Cons) for n in nodes):
        fn(*nodes)
        nodes = [n.cdr for n in nodes]
    return ls[0] if ls else NIL


def _format_iteration(dest, text, args):
    """~{ body ~} walks a list; ~^ stops before the last separator."""
    start = text.index("~{")
    end = text.rindex("~}")
    before, body, after = text[:start], text[start + 2 : end], text[end + 2 :]
    items = _seq(args[0]) if args else []
    sep_at = body.find("~^")
    item_fmt, separator = (body, "") if sep_at < 0 else (body[:sep_at], body[sep_at + 2 :])
    pieces = [cl_format(NIL, item_fmt, x) for x in items]
    out = (
        cl_format(NIL, before, *args[1:])
        + separator.join(pieces)
        + cl_format(NIL, after)
    )
    if dest is NIL:
        return out
    print(out, end="")
    return NIL


# --------------------------------------------------------------------------
# (declare (optimize (speed 3))) -- ask for machine code
#
# Common Lisp already has a way to say "make this fast", so no new syntax is
# needed.  A function declared this way is compiled without the Lisp value
# representation -- no NIL, no T-returning predicates, no block exception --
# and handed to Numba.  It is the safe/unsafe distinction Common Lisp has
# always had, made real.


def numba_njit(fn):
    """Compile FN with Numba if it is installed; otherwise leave it alone."""
    try:
        import numba
    except Exception:
        return fn
    return numba.njit(cache=False)(fn)


# --------------------------------------------------------------------------
# lazy streams
#
# A stream is a cons whose tail is a thunk, forced and memoised on demand.
# The structure stays in ordinary compiled code; what gets forced can be a
# function compiled for speed.


def cl_stream_cons(head, thunk):
    return Cons(head, thunk)


def cl_stream_car(s):
    return s.car


def cl_stream_cdr(s):
    if callable(s.cdr):
        s.cdr = s.cdr()
    return s.cdr


def cl_stream_take(n, s):
    out = []
    for _ in range(n):
        if s is NIL:
            break
        out.append(cl_stream_car(s))
        s = cl_stream_cdr(s)
    return from_iterable(out)


def cl_stream_nth(n, s):
    for _ in range(n):
        s = cl_stream_cdr(s)
    return cl_stream_car(s)


def cl_stream_map(f, s):
    if s is NIL:
        return NIL
    return Cons(f(cl_stream_car(s)), lambda: cl_stream_map(f, cl_stream_cdr(s)))
