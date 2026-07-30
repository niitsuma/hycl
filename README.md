# hyclb

Common Lisp that compiles to Python, with SBCL as the macroexpander.

Source is read and macroexpanded by a real Common Lisp implementation, but the
expansion is translated and compiled to Python bytecode. The Lisp is present
while the program is built and takes no part in running it — a build-time
dependency in the same sense as a compiler.

```lisp
;; fib.lisp
(defun fib (n)
  (loop for i from 0 below n
        collect (round (/ (- (expt 1.6180339887 i) (expt -0.6180339887 i))
                          2.2360679775))))
```

```python
import hyclb          # teaches Python's import system about .lisp files
import fib
print(fib.fib(10))
```

## Why

Python has the libraries; Common Lisp has the macros. Existing bridges make you
choose which runtime is in charge, and the choice decides which ecosystem
becomes second-class. Because macroexpansion finishes before a program runs, it
can be delegated to a real Common Lisp while the program itself runs on Python.

What that buys:

* **Macros written for Common Lisp work unchanged**, including libraries. A
  macro-only Quicklisp library expands away and never reaches the Python side,
  so `trivia`, `alexandria`, `iterate`, `anaphora`, `metabang-bind` and
  `let-over-lambda` are used as-is. A library with a runtime — `si-kanren`, a
  miniKanren — is compiled through the system instead.
* **Python objects are ordinary Lisp values.** No marshalling layer: a Torch
  tensor is stored in a Lisp variable and passed to Lisp functions unchanged.
* **CLOS with multiple dispatch**, which Python has no equivalent of.
* **Conditions are Python exceptions**, so `handler-case` catches what a Python
  library raises.
* **Common Lisp's own declarations drive the back end.** `(declare (type ...))`
  becomes a Python type annotation; `(declare (optimize (speed 3)))` selects a
  second compilation that Numba turns into machine code, and adding
  `(float-accuracy 0)` — an `optimize` quality of our own, which the standard
  permits an implementation to define — lets the reductions be vectorised.
  `benchmarks/lasso.py` measures what those two declarations are worth on a
  LASSO regression written in Common Lisp.

## The other direction

An existing Python program can be brought into the Lisp:

```
python -m hyclb.frompy script.py -o script.lisp
```

`hyclb.frompy` walks Python's own `ast` and emits Common Lisp — not Hy, which
is what [py2hy](https://github.com/niitsuma/py2hy) emits, but source that goes
through the SBCL expander like any other `.lisp` file, so a macro applies to it
straight away. It also means the declarations work: `examples/from_python.py`
translates a numeric loop and adds one `(declare (optimize (speed 3) ...))`,
which the Python it came from had no way to ask for.

The translation preserves behaviour rather than beauty. Where Common Lisp and
Python disagree, the Python operation is written explicitly, because a silent
change of meaning is worse than an ugly form:

| Python | Common Lisp would give | so the output says |
| --- | --- | --- |
| `10 / 4` | `5/2`, an exact rational | `(py-binop "/" 10 4)` |
| `a == b` | numeric or structural `=` | `(py-binop "==" a b)` |
| `if 0:` | `0` is true in Lisp | `(if (py-truthy 0) ...)` |
| `0 or 5` | `0`, since `0` is true | `(py-or 0 5)` |

On the fast path those wrappers collapse back into the operators, since there
the arithmetic is Python's already. `tests/test_frompy.py` is the real check:
each case runs as Python, is translated, is compiled back by hyclb, and the two
outputs must be identical — so the program is its own oracle. Anything with no
faithful translation raises `Unsupported` instead of guessing.

Whole modules go through. `tests/test_frompy_stdlib.py` translates ten of
Python's own — `colorsys`, `bisect`, `heapq`, `statistics`, `textwrap`,
`queue`, `copy`, `json.encoder`, `csv` and `random`, up to a thousand lines
each — compiles them with hyclb, and probes each one side by side with the
module CPython imported. All ten agree. Nobody wrote them for this translator,
which is the point.

## Installing

Not on PyPI: the name `hyclb` there still holds the 2020 implementation, which
this supersedes and which no current Hy can run. Install from the repository.

```
git clone https://github.com/niitsuma/hycl   # the repository is named hycl
pip install -e hycl                          # the package it installs is hyclb
```

The two names differ, inherited from 2020: you clone `hycl` and you
`import hyclb`.

SBCL must be on `PATH`; it is the macroexpander and cannot be installed by pip.

```
apt install sbcl        # Debian/Ubuntu
brew install sbcl       # macOS
```

Optional:

* **Quicklisp** — install it in the usual way to load Common Lisp libraries
  into the expander with `(ql:quickload "trivia")`.
* **Numba** (`pip install numba`) — for `(declare (optimize (speed 3)))`.
  Without it those functions still run, just not as machine code.
* **Maxima** — for driving a computer algebra system from a macro. Maxima is
  GPL v2 and is run as a separate process; it is neither linked nor
  distributed with hyclb, and the feature is optional.

## Using it

A `.lisp` file is an importable module once `hyclb` has been imported:

```python
import hyclb
import my_module          # compiles my_module.lisp, caches the bytecode
```

Compilation goes through Python's ordinary source-file machinery, so the result
is cached as bytecode beside the source and a second run needs no SBCL.

To compile a string or a file directly:

```python
from hyclb.api import cl_eval, cl_load, new_module

module = new_module("scratch")
cl_eval("(defun square (x) (* x x))", module)
print(module.square(7))
```

## Examples

`tests/` doubles as the example set:

| file | what it shows |
| --- | --- |
| `onlisp.lisp` | macros from *On Lisp*: anaphoric macros, hygiene, generalized variables |
| `maxima.lisp` | symbolic differentiation performed while the program compiles |
| `maxima-apps.lisp` | analytic gradients, subexpression elimination, series, identity checking |
| `lagrangian.lisp` | equations of motion derived from a Lagrangian, then simulated |
| `sequences.lisp` | a recurrence solved symbolically, streamed lazily, compiled to machine code |
| `defsum.lisp` | summed-area tables derived from the sum itself: the box-sum recurrence is obtained by telescoping in Maxima, refused when it does not hold, and the generated code is checked against the naive sum before it is accepted |
| `tailcall.lisp` | self-tail recursion compiled to a loop; mutual recursion left alone |
| `lasso.lisp` | LASSO by coordinate descent, compiled three ways; `benchmarks/lasso.py` times them against NumPy, scikit-learn and cuML |
| `sweep.lisp` | a hyperparameter grid built at compile time, driving PyTorch Lightning |
| `lightning_demo.lisp` | a LightningModule whose class definition a macro generates |
| `generators.lisp` | `yield` through every binding and control form; `async` |
| `clos.lisp` | classes, inheritance, multiple dispatch, method qualifiers |
| `kanren_demo.py` | compiling a Quicklisp library that is not macro-only |
| `test_frompy.py` | Python translated to Lisp and back, output compared |

## Tests

```
python -m pytest tests
```

or run a single suite directly:

```
python -c "import hyclb; from hyclb.api import cl_load; cl_load('tests/onlisp.lisp')"
```

Each suite prints `(pass ...)` or `(FAIL ...)` per case; `tests/test_suites.py`
turns that into pytest results. A suite that needs Maxima, Quicklisp or a
Python package the machine does not have is skipped with a reason rather than
failed, which is what lets CI run the rest.

One caveat worth knowing: a `.lisp` file shadows an installed package of the
same name, exactly as a `.py` file would — and an *empty* `.lisp` file shadows
it too, since the loader still claims the extension. The fix is to keep such
files off `sys.path`; `tests/__init__.py` exists so that pytest treats this
directory as a package rather than adding it to the path.

## How it works

1. SBCL reads one top-level form, under a readtable whose case is `:invert` so
   that a Common Lisp symbol can spell a Python identifier exactly.
2. Forms belonging to the expander — `defmacro`, `defpackage`, `ql:quickload` —
   are evaluated there and not translated.
3. Everything else is macroexpanded by a code walker that halts at a
   configurable *expansion frontier*.
4. The expansion is translated to Hy models and compiled to Python AST.

What survives macroexpansion is the twenty-five Common Lisp special operators
plus function calls, so the part that must be implemented is closed and small,
however many macros a program uses.

## Status

A research prototype. The package system is not implemented (symbols are known
by name alone), and Python's lack of tail calls limits *mutual* recursion --
a function that calls itself in tail position is compiled to a loop, so that
case is unbounded. `handler-bind` runs its handler after Python has already
unwound, so a handler can decline or transfer control but cannot inspect the
signalling frame. See the paper for the full list.

## Citing

A paper describing the design is in preparation and is not in this repository
yet. Until it appears, cite the repository and the commit you used.

## License

MIT. See [LICENSE](LICENSE).
