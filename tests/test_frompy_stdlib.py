"""Translate whole standard-library modules and check they still work.

The round-trip cases in test_frompy.py are written to exercise one construct at
a time. These are the opposite: real modules nobody wrote for this translator,
several hundred to a thousand lines each. Each is translated, compiled by
hyclb, and then probed side by side with the module CPython imported, so the
comparison is against the real implementation rather than against an
expectation.

They are slow -- SBCL macroexpands every form -- so this file is separate from
the quick cases.
"""

import importlib
import importlib.util
import io
import pathlib

import pytest

import hyclb  # noqa: F401
from hyclb.api import cl_eval, new_module
from hyclb.frompy import Unsupported, translate_source

# Each probe is run twice, once against CPython's module and once against the
# translated one; the two results must be equal.  Keep them deterministic --
# a seeded Random, no clock, no filesystem.
PROBES = {
    "colorsys": lambda m: (
        tuple(round(x, 9) for x in m.rgb_to_hls(0.2, 0.4, 0.6)),
        tuple(round(x, 9) for x in m.hls_to_rgb(0.5, 0.5, 0.5)),
        tuple(round(x, 9) for x in m.rgb_to_yiq(1, 0, 0)),
        tuple(round(x, 9) for x in m.rgb_to_hsv(0.1, 0.9, 0.4)),
    ),
    "bisect": lambda m: (
        m.bisect_left([1, 3, 5, 7], 5), m.bisect_right([1, 3, 5, 7], 5),
        m.bisect_left([1, 3, 5, 7], 4), m.bisect_right([1, 1, 1], 1),
        (lambda a: (m.insort(a, 4), a)[1])([1, 3, 5]),
    ),
    "heapq": lambda m: (
        m.nsmallest(3, [5, 1, 9, 3, 7]), m.nlargest(2, [5, 1, 9, 3, 7]),
        (lambda h: ([m.heappush(h, x) for x in (5, 1, 9, 2)],
                    [m.heappop(h) for _ in range(4)])[1])([]),
        (lambda a: (m.heapify(a), a)[1])([9, 4, 7, 1]),
        list(m.merge([1, 4, 7], [2, 3, 8])),
    ),
    "statistics": lambda m: (
        m.mean([1, 2, 3, 4]), m.median([1, 3, 2]), m.median_low([1, 2, 3, 4]),
        round(m.stdev([1, 2, 3, 4]), 12), round(m.variance([2, 4, 6]), 12),
        m.mode([1, 1, 2]), m.fmean([1, 2, 3]), m.quantiles([1, 2, 3, 4, 5]),
    ),
    "textwrap": lambda m: (
        m.wrap("the quick brown fox jumps over the lazy dog", 10),
        m.fill("a b c d e f", 3), m.shorten("hello there world", 12),
        m.indent("a\nb\n", "> "), m.dedent("    x\n    y\n"),
    ),
    "queue": lambda m: (
        (lambda q: ([q.put(i) for i in range(3)],
                    [q.get() for _ in range(3)], q.empty(), q.qsize())[1:])(
            m.Queue()),
        (lambda q: ([q.put(i) for i in (3, 1, 2)],
                    [q.get() for _ in range(3)])[1])(m.PriorityQueue()),
        (lambda q: ([q.put(i) for i in (1, 2)],
                    [q.get() for _ in range(2)])[1])(m.LifoQueue()),
    ),
    "copy": lambda m: (
        m.copy([1, [2]]), m.deepcopy({"a": [1, 2]}),
        (lambda o, c: (o[0] is c[0], o == c))([[1]], m.deepcopy([[1]])),
    ),
    "json.encoder": lambda m: (
        m.JSONEncoder().encode({"a": [1, 2], "b": "x"}),
        m.JSONEncoder(sort_keys=True).encode({"b": 1, "a": 2}),
        m.JSONEncoder(indent=2).encode([1, {"k": True}]),
        m.encode_basestring_ascii("café\n"),
    ),
    "csv": lambda m: (
        (lambda buf: (m.writer(buf).writerows([["a", "b,c"], ["1", "2"]]),
                      buf.getvalue().replace("\r\n", "|"))[1])(io.StringIO()),
        list(m.reader(["x,y", "1,2"])),
        [dict(r) for r in m.DictReader(["a,b", "1,2"])],
    ),
    "random": lambda m: (
        (lambda r: (r.random(), r.randint(1, 100), r.randrange(5, 50, 5),
                    r.sample(range(20), 4), r.choice("abcdef"),
                    (lambda xs: (r.shuffle(xs), xs)[1])(list(range(8))),
                    round(r.gauss(0, 1), 12), round(r.expovariate(1.5), 12),
                    ))(m.Random(1234)),
    ),
}

SLOW = pytest.mark.slow


def _translated(name):
    origin = importlib.util.find_spec(name).origin
    source = pathlib.Path(origin).read_text()
    try:
        lisp, _ = translate_source(source, origin)
    except Unsupported as e:
        pytest.skip(f"not translatable yet: {e}")
    module = new_module(name.replace(".", "_") + "_via_lisp")
    cl_eval(lisp, module)
    return module


@SLOW
@pytest.mark.parametrize("name", sorted(PROBES))
def test_stdlib_module(name):
    probe = PROBES[name]
    expected = probe(importlib.import_module(name))
    got = probe(_translated(name))
    assert got == expected
