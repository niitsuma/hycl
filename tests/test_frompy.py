"""Round-trip test for the Python-to-Lisp translator.

Each case is a Python program that prints something. It is run as Python, then
translated to Common Lisp, then compiled back to Python by hyclb and run again.
The two outputs must be identical -- which makes the original program its own
oracle, so a mistranslation cannot pass by being plausible.
"""

import contextlib
import io
import textwrap

import pytest

import hyclb  # noqa: F401
from hyclb.api import cl_eval, new_module
from hyclb.frompy import Unsupported, translate_source

CASES = {
    "arithmetic": """
        print(1 + 2, 7 - 3, 4 * 5)
        print(10 / 4, 10 // 4, 10 % 3, 2 ** 10)
        print(-7 // 2, -7 % 3)
        print(1 << 4, 255 & 15, 8 | 1, 5 ^ 3, ~5)
    """,
    "python-truth": """
        for v in [0, 1, "", "x", [], [0], None]:
            print(bool(v), "yes" if v else "no", not v)
        print(0 or 5, 1 or 5, 0 and 5, 2 and 5)
    """,
    "equality": """
        print([1, 2] == [1, 2], [1, 2] is [1, 2], "a" == "a")
        print(1 == 1.0, 1 is 1.0, 3 != 4)
        print(2 in [1, 2, 3], 9 not in [1, 2, 3], "b" in "abc")
    """,
    "ordering-chains": """
        print(1 < 2, 2 <= 2, 3 > 4, 4 >= 4)
        print(1 < 2 < 3, 3 < 2 < 1)
        print("a" < "b", [1, 2] < [1, 3])
    """,
    "control-flow": """
        def sign(n):
            if n > 0:
                return "pos"
            elif n < 0:
                return "neg"
            return "zero"

        print(sign(3), sign(-3), sign(0))

        total = 0
        i = 0
        while i < 10:
            i += 1
            if i % 2 == 0:
                continue
            if i > 7:
                break
            total += i
        print(total, i)
    """,
    "loops": """
        acc = []
        for x in range(5):
            for y in range(x):
                if y == 2:
                    continue
                acc.append((x, y))
        print(acc)
        print([i * i for i in range(8) if i % 3])
        print({k: k * 2 for k in range(4)})
        print(sorted({i % 3 for i in range(10)}))
    """,
    "functions": """
        def greet(name, greeting="hello"):
            return greeting + " " + name

        def count(*args):
            return len(args)

        def outer(n):
            def inner(k):
                return k * n
            return inner(3)

        print(greet("world"), greet("world", "hi"))
        print(count(1, 2, 3), count())
        print(outer(5))
        print((lambda a, b: a * b)(6, 7))
    """,
    "starred-calls": """
        def f(a, b, c=0):
            return (a, b, c)

        args = [1, 2]
        kw = {"c": 3}
        print(f(*args))
        print(f(*args, **kw))
        print(f(1, **{"b": 2, "c": 9}))
    """,
    "classes": """
        class Shape:
            kind = "shape"

            def __init__(self, n):
                self.n = n

            def describe(self):
                return self.kind + ":" + str(self.n)

        class Square(Shape):
            kind = "square"

            def area(self):
                return self.n * self.n

        s = Square(4)
        print(s.describe(), s.area(), isinstance(s, Shape))
    """,
    "strings": """
        x = 1 / 3
        n = 42
        print(f"{n} and {x:.3f}")
        print(f"{n!r} {'q'!r}")
        print("a,b,c".split(","), "-".join(["x", "y"]))
        print("Hello"[1:4], "Hello"[::-1], "Hello"[-2:])
    """,
    "collections": """
        d = {"a": 1, "b": 2}
        d["c"] = 3
        del d["a"]
        print(sorted(d.items()), len(d), "b" in d)
        t = (1, 2, 3)
        print(t[1], list(t), tuple([4, 5]))
        xs = [3, 1, 2]
        xs.sort()
        print(xs, xs[0], xs[-1], xs[0:2])
    """,
    "unpacking": """
        a, b = 1, 2
        a, b = b, a
        print(a, b)
        (p, q), r = (1, 2), 3
        print(p, q, r)
        x = y = 7
        print(x, y)
    """,
    "exceptions": """
        def safe(a, b):
            try:
                return a / b
            except ZeroDivisionError:
                return "nope"
            finally:
                print("done")

        print(safe(10, 4))
        print(safe(1, 0))

        try:
            raise ValueError("boom")
        except ValueError as e:
            print("caught", e)
    """,
    "generators": """
        def upto(n):
            i = 0
            while i < n:
                yield i
                i += 1

        print(list(upto(5)))
        print(sum(upto(10)))
    """,
    "globals": """
        counter = 0

        def bump():
            global counter
            counter += 1
            return counter

        print(bump(), bump(), counter)
    """,
    "with-statement": """
        import io

        with io.StringIO() as buf:
            buf.write("hello")
            print(buf.getvalue())
    """,
    "imports": """
        import math
        import os.path as p
        from math import sqrt, pi

        print(round(math.sqrt(16)), round(sqrt(25)), round(pi, 2))
        print(p.basename("/a/b/c.txt"))
    """,
    "name-collisions": """
        # every one of these means something else to hyclb
        print(list(map(abs, [-1, 2, -3])))
        print(len(list(range(3))), max(1, 2), min(1, 2), round(2.5))
        print(sorted([3, 1, 2]), sum([1, 2, 3]))
        print(format(1 / 3, ".2f"), str(12), int("12"), float("1.5"))
    """,
    "shadowed-builtin": """
        def count(xs):
            # shadows nothing in Python, but `count` is a Lisp function
            return len(xs)

        list = [1, 2, 3]
        print(count(list), list)
    """,
}


def _run_python(source):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        exec(compile(source, "<case>", "exec"), {"__name__": "__main__"})
    return out.getvalue()


def _run_lisp(lisp, name):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        cl_eval(lisp, new_module(name))
    return out.getvalue()


@pytest.mark.parametrize("name", sorted(CASES))
def test_round_trip(name):
    source = textwrap.dedent(CASES[name]).strip() + "\n"
    expected = _run_python(source)
    try:
        lisp, _ = translate_source(source, name)
    except Unsupported as e:
        pytest.skip(f"not translatable yet: {e}")
    got = _run_lisp(lisp, "rt_" + name)
    assert got == expected, (
        f"round trip differs for {name}\n"
        f"--- python ---\n{expected}--- via lisp ---\n{got}"
        f"--- the lisp ---\n{lisp}"
    )


def test_unsupported_is_reported():
    """A construct with no faithful translation must raise, not guess."""
    with pytest.raises(Unsupported):
        translate_source("match x:\n    case 1: pass\n")
