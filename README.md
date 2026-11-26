# hyclb

Common Lisp that compiles to Python, with SBCL as the macroexpander.

Source is read and macroexpanded by a real Common Lisp implementation, but the
expansion is translated and compiled to Python bytecode. The Lisp is present
while the program is built and takes no part in running it — a build-time
dependency in the same sense as a compiler.

## Examples

### Write Common Lisp, import it as Python

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

A declaration can make a function faster, sometimes very much faster, by
compiling it through Numba; how much is a question for measurement, and
[`benchmarks/RESULTS.md`](benchmarks/RESULTS.md) has the numbers.

### Let a macro do what the source cannot say

In [`examples/model_math.lisp`](examples/model_math.lisp) a Lisp macro
derives the derivative of an activation function — symbolically, in Maxima,
while the program compiles — and generates a `torch.autograd.Function` whose
backward pass is that closed form. No tape, no autograd; the gradient was
decided before Python started:

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

### The same seat, occupied by a language model

The expander may consult any process it likes while the program compiles, and
[`examples/llm_macro.lisp`](examples/llm_macro.lisp) puts a local LLM where
the previous example put Maxima. The difference is trust: algebra is
accepted, a sampled answer never is, so `defllm` refuses to expand without
`:check` clauses, evaluates the model's expression against them in SBCL, and
sends a failure back for another attempt. Three failures are a compile-time
error, the same treatment `defsum` gives a sum that does not telescope.

```lisp
(defllm clamp (x lo hi)
  "x limited to the closed interval [lo, hi]"
  (:check (5 0 10) 5)
  (:check (-3 0 10) 0)
  (:check (42 0 10) 10))
```

An answer is judged twice, and the first pass never runs it: SBCL compiles
the expression and reports undefined names, wrong argument counts, malformed
binding forms, `go` to a nonexistent tag and declared-type conflicts, all
statically. Only what compiles is then run against the checks. Hy cannot be
asked the same question — Python resolves names when the code runs, so every
one of those mistakes compiles clean there and surfaces as a traceback — and
that asymmetry is the reason the expander is the right place for this.

What survives is an ordinary `defun` — this one comes back as
`(max lo (min x hi))` — translated like anything else. The compiled program
depends on the model exactly as much as it depends on Maxima, which is not at
all, and since compiled modules are cached as bytecode, the model is consulted
when the source changes, not on every run.

The model is reached through a command-line program, `ask-local` by default:
it is called as

```console
$ ask-local --model qwen3.6 --max-tokens 400 --system "You write Common Lisp. …" \
    "Write the body of a Common Lisp function CLAMP with parameters (X LO HI). …"
(max lo (min x hi))
```

and anything with that shape will do — a script around `llama.cpp`, an
OpenAI-compatible endpoint, whatever is local and cheap. `HYCLB_LLM` names a
different program, `HYCLB_LLM_MODEL` a different model. Credentials are the
program's own affair; nothing secret appears in the source being compiled or
in this repository.

A `(:tolerance eps)` clause loosens the numeric comparisons, and that turns
the checks into sampled data: give the model measured points and ask it for
the function underneath. In `examples/llm_macro.lisp` thirteen samples of an
unnamed function go in with `(:tolerance 0.01)` and nothing that says sine —
the model recognises the shape in the numbers and comes back with `(sin x)`,
which the example then compares against the sine the samples were taken from
on a hundred points the model never saw. Symbolic regression, one prompt
long; had the model answered with a polynomial instead, the checks would
have judged the fit the same way.

```lisp
(defllm recovered-f (x)
  "a smooth closed-form function fitting the sampled points"
  (:tolerance 0.01)
  (:check (0.0) 0.0)
  (:check (0.5236) 0.5)
  (:check (1.0472) 0.866)
  ;; … thirteen points over one period …
  (:check (6.2832) 0.0))
```

For a question that is not a function there are three doors, one per kind of
answer, and each snippet is judged by the compiler of the language it is
written in. One request asked three ways — *x·y plus the numeric value of
pi* — shows what each is for:

```lisp
(ask-llm        "In one sentence, what does x*y plus pi compute?")
;; => "The product of x and y plus the mathematical constant pi."

(ask-llm-form   "x times y, plus the numeric value of pi" :free (x y))
;; => (+ (* x y) pi)                      SBCL compiles it, here, without running it

(ask-llm-python "x*y plus the numeric value of pi")
;; => (progn (py-import math) (+ (* x y) math.pi))    CPython parses it, frompy translates it
```

`ask-llm` returns a **string**. Nothing can check it and nothing needs to: it
can become documentation, a message, a generated comment — data that a wrong
answer makes *wrong* rather than *broken*.

`ask-llm-form` returns **Common Lisp code**, spliced in where the macro
stood. `:free` names the variables the expression may use, and that is what
makes the answer checkable at all: with it, SBCL compiles the form and calls
every other name undefined. The form is compiled, never run, and the
compiler's own complaint is what goes back to the model.

`ask-llm-python` returns a **Python expression**, translated by `hyclb.frompy`
into the same Lisp a `.py` file would have produced — so nothing downstream
special-cases it. CPython's parser is the verdict on whether the reply is an
expression at all, and a `SyntaxError` goes back to the model. Python cannot
say whether the *names* exist, which is exactly how much looser this door is
than `ask-llm-form`; the modules a dotted name reaches through are read off
the expression and imported, since an expression has no room to say
`import math` for itself.

Anything whose *value* matters should still go through `defllm`, where the
`:check` clauses decide — these three check that the answer is well formed,
not that it is right. All three ask in the expander, so what reaches the
compiled program is the answer and the model is not there to be asked again;
one question asked twice while a file compiles is answered once. `llm-ask` is
the plain function underneath, callable from any macro you write yourself.

All five are in the one example, which runs like the others:

```console
$ python -c "from hyclb.api import cl_load, new_module; \
    m = new_module('llm'); cl_load('examples/llm_macro.lisp', m); m.main()"
(says "The expression computes the sum of the product of x and y and the mathematical constant pi.")
(lisp-arm 15.141592653589793 python-arm 15.141592653589793 agree yes)
(clamped 7)
(february 2100 has 28 days)
(recovered-f max-error-vs-sin 0.0)
(agrees-with-python-calendar T)
```

Line by line: the string door answered in prose, and its wording is the one
thing here that changes from run to run. The Lisp and Python doors were
handed the same request and agree to the last digit, having arrived at `pi`
and `math.pi` respectively. `clamp` and `days-in-month` are `defllm`
functions, and the last two lines are the parts that check the model's work
on inputs it never saw — the recovered sine against the sine the samples came
from, and `days-in-month` against Python's own `calendar` module for sixty
month/year pairs.

[`tests/llm.lisp`](tests/llm.lisp) is the checked version of all of it: the
expansion-time checks prove the Lisp, and the suite then proves the
translation.

### Bring existing Python into the Lisp

`hyclb.frompy` walks Python's own `ast` and emits Common Lisp — not Hy, which
is what [py2hy](https://github.com/niitsuma/py2hy) emits, but source that goes
through the SBCL expander like any other `.lisp` file, so macros and
declarations apply to it straight away:

```console
$ python -m hyclb.frompy moments.py
```

```lisp
(defun mean (xs)
  (setq total 0.0)
  (py-for (x xs) (setq total (+ total x)))
  (py-binop "/" total (py-call len xs)))
```

Where the two languages agree — `+`, `-`, `*`, the orderings — the Lisp
operator is used. Where they disagree the Python one is written explicitly,
because a silent change of meaning is worse than an ugly form: Common Lisp's
`/` is exact, so `total / len(xs)` becomes `(py-binop "/" ...)` rather than a
rational.

The translation is checked by round-tripping: each of nineteen programs is run
as Python, translated, compiled back by hyclb, and the two outputs compared,
so the program is its own oracle
([`tests/test_frompy.py`](tests/test_frompy.py)).

Ten modules of Python's own standard library then go through whole. Each is
translated, compiled by hyclb, and probed side by side with the module CPython
imported; all ten agree on every probe. Nobody wrote them for this translator,
which is the point.

| module | lines | what the probe checks |
| --- | ---: | --- |
| `colorsys` | 166 | RGB↔HLS, ↔YIQ, ↔HSV round trips |
| `bisect` | 118 | `bisect_left`/`right`, `insort`, ties |
| `heapq` | 603 | push/pop, `heapify`, `nsmallest`, `merge` |
| `statistics` | 1,454 | mean, median, stdev, variance, mode, quantiles; on 3.13 it needs `match` |
| `textwrap` | 491 | `wrap`, `fill`, `shorten`, `indent`, `dedent` |
| `queue` | 326 | FIFO, LIFO and priority queues |
| `copy` | 292 | shallow against deep, and identity after |
| `json.encoder` | 443 | encoding, `sort_keys`, `indent`, ASCII escaping |
| `csv` | 451 | writing with embedded commas, reading, `DictReader` |
| `random` | 996 | a seeded `Random`: `randint`, `sample`, `shuffle`, `gauss` |

The probes are [`tests/test_frompy_stdlib.py`](tests/test_frompy_stdlib.py);
run them with `pytest tests/test_frompy_stdlib.py`. Translating is not
running, and it was running that found the real problems — class bodies are
scopes executed in order, name resolution is per-scope, and a Python function
that falls off the end returns `None` where a Lisp body returns its last form.

[`examples/from_python.py`](examples/from_python.py) translates a numeric loop
and then adds one `(declare (optimize (speed 3) ...))`, which the Python it
came from had no way to ask for.

### Compiling without the import hook

To compile a string or a file directly, rather than through `import`:

```python
from hyclb.api import cl_eval, cl_load, new_module

module = new_module("scratch")
cl_eval("(defun square (x) (* x x))", module)
print(module.square(7))
```

### The rest

`tests/` doubles as the example set:

| file | what it shows |
| --- | --- |
| `onlisp.lisp` | macros from *On Lisp*: anaphoric macros, hygiene, generalized variables |
| `maxima.lisp` | symbolic differentiation performed while the program compiles |
| `maxima-apps.lisp` | analytic gradients, subexpression elimination, series, identity checking |
| `lagrangian.lisp` | equations of motion derived from a Lagrangian, then simulated |
| `sequences.lisp` | a recurrence solved symbolically, streamed lazily, compiled to machine code |
| `defsum.lisp` | summed-area tables derived from the sum itself, and `lift-sums`, which recognises the naive nest and rewrites it back into one: the box-sum recurrence is obtained by telescoping in Maxima, refused when it does not hold, and the generated code is checked against the naive sum before it is accepted |
| `llm.lisp` | the four LLM macros: `defllm`, whose body must pass its `:check` clauses in SBCL before it is admitted, and `ask-llm` / `ask-llm-form` / `ask-llm-python`, checked by nobody, by SBCL, and by CPython respectively |
| `tailcall.lisp` | self-tail recursion compiled to a loop; mutual recursion left alone |
| `lasso.lisp` | LASSO by coordinate descent, compiled three ways; `benchmarks/lasso.py` times them against NumPy, scikit-learn and cuML |
| `sweep.lisp` | a hyperparameter grid built at compile time, driving PyTorch Lightning |
| `lightning_demo.lisp` | a LightningModule whose class definition a macro generates |
| `generators.lisp` | `yield` through every binding and control form; `async` |
| `clos.lisp` | classes, inheritance, multiple dispatch, method qualifiers |
| `kanren_demo.py` | compiling a Quicklisp library that is not macro-only |
| `test_frompy.py` | Python translated to Lisp and back, output compared |

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
There are 57 items. A bare install — Hy and SBCL, nothing else — passes 45 and
skips 12: five suites want Maxima, four want numpy or torch, two want
Quicklisp, and one wants the language-model CLI. Installing those turns skips
into passes one group at a time; with everything present, 56 pass.

The one that does not become a pass on this machine is `libraries.lisp`:
`let-over-lambda` does not build under SBCL 2.5.11 with the current Quicklisp
dist, which plain SBCL confirms, so the suite skips rather than blaming hyclb
for it. And `llm.lisp` asks a live language model, so it is the one suite
whose result is sampled rather than determined — an unlucky answer can fail
it. That is why it is not in the sdist.

### Common problems

**`FileNotFoundError: 'sbcl'`** — SBCL is not on `PATH`. `python -m hyclb`
reports this before anything else.

**A test imports numpy and fails** rather than skipping — that means the
package is installed but broken (a numba without a numpy, say). hyclb decides
by importing, so fix the package or uninstall it.

**Editing hyclb has no effect** — compiled `.lisp` files are cached as
bytecode. The cache key includes a hash of hyclb's own sources, so this should
not happen; if it does, remove the `__pycache__` beside your `.lisp` file.

**`TypeError: expected string or bytes-like object, got 'NoneType'`** while pip
is generating metadata, raised inside `setuptools/installer.py` — a
Debian/Ubuntu collision that has nothing to do with hyclb, and whose message
names neither hyclb nor the real cause. `python3-charset-normalizer` ships a
`.dist-info` directory containing only an `INSTALLER` file; with no `METADATA`
in it, `importlib.metadata` reports that distribution's name as `None`, and
setuptools canonicalises the name of every installed distribution without
guarding for it. It is reachable only through the legacy `setup_requires` path,
which pip avoids by building in isolation — the venv install above is
unaffected, and installs into the system Python (`--user`,
`--break-system-packages`) are the ones that can meet it. Any one of these
clears it:

```console
$ python -m venv .venv && . .venv/bin/activate    # the venv is not affected
$ pip install wheel funcparserlib                 # found first, so the scan stops early
$ sudo mv /usr/lib/python3.12/dist-packages/charset_normalizer-*.dist-info{,.disabled}
```

The last one is undone by the next update of that apt package.

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
* **Common Lisp's own declarations drive the back end**, so none of this
  needed a syntax of its own. `(declare (type ...))` becomes a Python type
  annotation, which is not decoration — dataclasses and pydantic read them at
  run time — and the *return* annotation needs no declaration at all: the
  expander compiles the function and asks SBCL what it derived. The same
  answer decides when the fast path is unsafe. A function returning
  `(expt 2 (- n))` has a `RATIONAL` value, which a machine word cannot hold,
  so `(optimize (speed 3))` on it is refused with a message rather than
  compiled into a silent zero. `(declare (optimize (speed 3)))` selects a second compilation
  without the Lisp value representation, which Numba turns into machine code:
  on LASSO regression that is 2,134× between the two compilations of one
  source text, and level with scikit-learn's hand-tuned Cython solver.
  Adding `(float-accuracy 0)`, which licenses the reassociation that lets a
  reduction vectorise, is worth a further 1.2–1.8×; it is an `optimize`
  quality of our own, which the standard permits an implementation to define.
  Where a GPU helps and where it does not is measured too, and the answer is
  not what one would guess.

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
signalling frame. Multiple values travel beside the first value rather than
with the call: a function that returns, alone, the first value of a form it
evaluated earlier -- `(let ((q (floor n 2))) q)` -- still hands the remainder
to a caller that asks with `multiple-value-bind`, where Lisp gives one value.
See the paper for the full list.

## Citing

A paper describing the design is in preparation and is not in this repository
yet. Until it appears, cite the repository and the commit you used.

## License

MIT. See [LICENSE](LICENSE).
