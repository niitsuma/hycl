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
  second compilation that Numba turns into machine code.

## Installing

```
pip install hyclb
```

SBCL must be on `PATH`; it is the macroexpander and cannot be installed by pip.

```
apt install sbcl        # Debian/Ubuntu
brew install sbcl       # macOS
```

Optional:

* **Quicklisp** — install it in the usual way to load Common Lisp libraries
  into the expander with `(ql:quickload "trivia")`.
* **Numba** (`pip install hyclb[fast]`) — for `(declare (optimize (speed 3)))`.
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
| `sweep.lisp` | a hyperparameter grid built at compile time, driving PyTorch Lightning |
| `lightning_demo.lisp` | a LightningModule whose class definition a macro generates |
| `generators.lisp` | `yield` through every binding and control form; `async` |
| `clos.lisp` | classes, inheritance, multiple dispatch, method qualifiers |
| `kanren_demo.py` | compiling a Quicklisp library that is not macro-only |

## Tests

```
python -m pytest tests
```

or run a single suite directly:

```
python -c "import hyclb; from hyclb.api import cl_load; cl_load('tests/onlisp.lisp')"
```

Each suite prints `(pass ...)` or `(FAIL ...)` per case; `tests/test_suites.py`
turns that into pytest results.

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
by name alone), `call-next-method` and `handler-bind` are absent, and Python's
lack of tail calls limits deeply recursive code. See the paper for the full
list.

## Citing

See `paper-en.tex` in the repository.

## License

MIT. See [LICENSE](LICENSE).
