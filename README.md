# hyclb

Common Lisp that compiles to Python, with SBCL as the macroexpander.

Source is read and macroexpanded by a real Common Lisp implementation, but the
expansion is translated and compiled to Python bytecode. The Lisp is present
while the program is built and takes no part in running it — a build-time
dependency in the same sense as a compiler.

```lisp
;; robust.lisp — Common Lisp on the outside, numpy underneath
(py-import numpy)

(defun zscores (xs)
  "Each point's distance from the mean, in standard deviations."
  (let ((mu (numpy.mean xs))
        (sd (numpy.std xs)))
    (loop for x in xs collect (/ (- x mu) sd))))

(defun outliers (xs threshold)
  "The points whose z-score exceeds THRESHOLD."
  (loop for x in xs
        for z in (zscores xs)
        when (> (abs z) threshold)
          collect x))

(defun clean-mean (xs threshold)
  "The mean, after dropping the outliers."
  (let ((bad (outliers xs threshold)))
    (numpy.mean (remove-if (lambda (x) (member x bad)) xs))))
```

**There is no translation command to run.** Import it:

```python
import hyclb            # teaches Python's import system about .lisp files
import robust           # compiles robust.lisp — there is no separate step

data = [4.9, 5.1, 5.0, 4.8, 5.2, 12.7, 5.0, 4.9]
print(list(robust.outliers(data, 2)))
print(robust.clean_mean(data, 2))
```

```
[12.7]
4.985714285714286
```

`import hyclb` registers a loader for the `.lisp` extension, and from then on
Python treats `.lisp` exactly as it treats `.py`: `import robust` finds the
source, compiles it, and caches the bytecode beside it as
`__pycache__/robust.cpython-312.pyc`. The second import reuses that cache and
never starts SBCL — the Lisp is needed to build the module, not to import it.

Inside, `loop … when … collect` is Common Lisp's `LOOP`, macroexpanded by
SBCL; `numpy.mean` is numpy's own, handed the list unconverted. What comes
out are ordinary Python functions, so `clean-mean` answers as
`robust.clean_mean`.

Macros are where it stops being a syntax. In
[`examples/model_math.lisp`](examples/model_math.lisp) a macro derives the
derivative of an activation function — symbolically, in Maxima, while the
program compiles — and generates a `torch.autograd.Function` whose backward
pass is that closed form. No tape, no autograd; the gradient was decided
before Python started:

```lisp
;; model_math.lisp — the parts easier to derive than to write
(defmacro defactivation (name (x) expr)
  (let ((slope (maxima-diff expr x)))       ; d/dx, computed by Maxima
    `(setq ,name (py-class ...))))          ; forward = expr, backward = slope

;; swish(x) = x · sigmoid(x); its backward pass is derived, not written
(defactivation swish (x) (/ x (+ 1 (exp (- x)))))
```

[`examples/main.py`](examples/main.py) is an ordinary Python program that
imports this module and checks the derived gradient against Torch's autograd
on the same function:

```python
import torch
import hyclb
import model_math

x = torch.tensor([-1.0, 0.0, 1.0, 2.0], requires_grad=True)
model_math.swish.apply(x).sum().backward()
```

```
analytic gradient = [0.072329, 0.5, 0.927671, 1.090784]
torch autograd    = [0.072329, 0.5, 0.927671, 1.090784]
agree             = True
```

The full program also trains a small network through the derived activation,
because the point is that nothing downstream can tell.

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
  [`benchmarks/RESULTS.md`](benchmarks/RESULTS.md) has the measured
  figures: what the declarations are worth, where the GPU helps and where it
  does not, and how the result compares with scikit-learn and with C++.

## Installing

hyclb needs two things: Hy, which pip installs, and SBCL, which it cannot.
Everything else is optional and buys a specific feature.

### 1. SBCL

SBCL is the macroexpander. It runs while a `.lisp` file is compiled and takes
no part in running the result, so it is a build-time dependency in the same
sense as a compiler — but without it nothing compiles at all.

```console
$ sudo apt install sbcl          # Debian, Ubuntu
$ brew install sbcl              # macOS
$ sudo dnf install sbcl          # Fedora
```

Any SBCL from the last several years will do; the tests run on 2.2.

### 2. hyclb

Not on PyPI: the name `hyclb` there still holds the 2020 implementation, which
this supersedes and which no current Hy can run. Install from the repository.
Note the two names — you clone `hycl` and you `import hyclb`, an inheritance
from 2020.

```console
$ git clone https://github.com/niitsuma/hycl
$ python -m venv .venv && . .venv/bin/activate
$ pip install -e hycl
```

Python 3.9 or later. `-e` is not required, but the examples and tests live in
the checkout, so an editable install keeps them where you can run them.

### 3. Check that it works

```console
$ python -m hyclb
```

This prints what is present and what is missing, then compiles a Common Lisp
function to Python and runs it. If it ends with `This installation works.`,
the required half is in place.

```
required
  Python       3.12.3
  Hy           1.3.0
  SBCL         SBCL 2.2.9.debian

optional
  NumPy        2.2.6
  Numba        0.61.2
  Maxima       /usr/bin/maxima
  Quicklisp    /home/you/quicklisp
  PyTorch      absent -- the Lightning and autograd examples (pip install torch lightning)

compiling a Lisp function to Python ... ok
```

### Optional pieces

Each of these is genuinely optional: without it the rest of hyclb works and
the parts that need it say so rather than failing.

| Install | What it buys |
| --- | --- |
| `pip install numpy` | arrays. Most of the examples use them, and the fast path is only interesting over them |
| `pip install numba` | `(declare (optimize (speed 3)))` becomes machine code. Without it, such functions still run, just as ordinary Python |
| `apt install maxima` | a computer algebra system inside compilation: symbolic derivatives, closed forms, identity checks |
| [Quicklisp](https://www.quicklisp.org/beta/#installation) | Common Lisp libraries in the expander — `(ql:quickload "trivia")`. Install it as usual; hyclb looks in `~/quicklisp`, or `$QUICKLISP_HOME` |
| `pip install torch lightning` | the PyTorch examples |

`pip install -e 'hycl[fast]'` installs numpy and numba together; add `test`
for pytest.

Maxima is GPL v2 and is run as a separate process — neither linked nor
distributed with hyclb.

### Running the tests

```console
$ pip install -e 'hycl[test]'
$ cd hycl && python -m pytest tests
```

Suites needing something absent skip with a stated reason rather than failing.
Measured on this checkout: a bare install (Hy and SBCL only) passes 46 and
skips 5; with `[fast]` — numpy and numba — it passes 49 and skips 2; with
torch and lightning as well, all 51 pass.

### Common problems

**`FileNotFoundError: 'sbcl'`** — SBCL is not on `PATH`. `python -m hyclb`
reports this before anything else.

**A test imports numpy and fails** rather than skipping — that means the
package is installed but broken (a numba without a numpy, say). hyclb decides
by importing, so fix the package or uninstall it.

**Editing hyclb has no effect** — compiled `.lisp` files are cached as
bytecode. The cache key includes a hash of hyclb's own sources, so this should
not happen; if it does, remove the `__pycache__` beside your `.lisp` file.

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
turns that into pytest results, and skips a suite whose dependency is absent.

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
