# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

hyclb compiles Common Lisp to Python by delegating macroexpansion to SBCL. A
persistent SBCL subprocess reads and macroexpands the source; what comes back
is translated to Hy models and compiled to Python bytecode. **No Lisp is
present when the compiled program runs** — SBCL is a build-time dependency in
the same sense as a compiler. Keep that invariant: anything that would make
the runtime need SBCL is a design error.

The repository is named `hycl`; the package is `hyclb`. Both names are
inherited from the 2020 version and are not interchangeable.

## Commands

```bash
pip install -e '.[fast,test]'        # numpy, numba, pytest
python -m hyclb                      # installation check; compiles and runs a form
python -m pytest tests               # everything
python -m pytest tests -k onlisp     # one suite
python -m pytest tests -q -rs        # see why suites skipped
```

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1` is often needed on developer machines:
unrelated pytest plugins in the user site-packages break collection.

Run a single Lisp suite outside pytest — much faster to iterate on, and it
prints the `(pass ...)` / `(FAIL ...)` lines directly:

```bash
python -c "import hyclb; from hyclb.api import cl_load; cl_load('tests/onlisp.lisp')"
```

Inspect what the front end produced, which is the first thing to do when a
form misbehaves:

```python
from hyclb.api import expand, to_models
expand("(dolist (x l) (print x))")      # what SBCL handed back
import hy; hy.repr(to_models(src)[0])   # the Hy form we generated
```

Translate Python into the Lisp:

```bash
python -m hyclb.frompy script.py -o script.lisp
```

## Architecture

Compilation is a pipeline across two processes and three languages. Reading
any one file will not show you the whole path; a change usually touches two or
three of these in step.

```
.lisp source
  → sbcl.py       persistent SBCL subprocess, line protocol
  → bridge.lisp   read (readtable-case :invert), macroexpand to the frontier,
                  rename gensyms, print back with source offsets
  → reader.py     parse SBCL's printed output into Cons/Symbol
  → translate.py  expanded CL forms → Hy models
  → cl.hy         the special operators, as Hy macros
  → Hy compiler → Python AST → bytecode
runtime.py is what the generated code calls; it is not in the pipeline.
```

### The two ideas the design rests on

**Closed translation surface.** After macroexpansion only the 25 CL special
operators plus function calls remain, whatever macros the program used. That
is why the back end is small and why macros nobody wrote for this system work.

**Expansion frontier** (`STOP` in `api.py`). Operators at which expansion
halts so the back end can translate them itself, instead of expanding into
SBCL internals. Raising it improves generated code; lowering it improves
compatibility. Two traps, both already paid for:

- The walker must use `macroexpand-1` in a loop. `macroexpand` sails past the
  frontier in one step.
- `walk-stopped` must re-enter a stopped form's non-name arguments, or
  stopping at `DEFUN` leaves every function body unexpanded.

Adding an operator to `STOP` means, in step: an entry in `SPECIAL`
(translate.py), a macro in cl.hy, usually an entry in `_STRUCTURAL`, and
sometimes a `*stop-skip*` or a clause-shape walker in bridge.lisp.

### Where each layer's rules live

**translate.py** — `SPECIAL` maps CL operators to cl.hy macro names; `RUNTIME`
maps CL functions to runtime.py names; `_STRUCTURAL` says which argument
positions are *not* code (`name`, `binding`, `bindings`, `names`, `fname`,
`raw`, `tags`, `all-names`). Getting `_STRUCTURAL` wrong is a common bug and
fails quietly: a compound `dotimes` bound was silently truncated because the
spec was declared `bindings` (a list of bindings) where it is one `binding`.

The fast path is a second set of tables — `FAST_SPECIAL`, `FAST_RUNTIME`,
`FAST_APPROX_SPECIAL` — selected by `_fast` / `_approx`, which
`(declare (optimize (speed 3)))` and `(float-accuracy 0)` set.

**cl.hy** — the special operators as macros. Two rules that are not
negotiable:

- **Binding forms and control structures expand inline, never into a
  function.** A hidden lambda silently breaks `yield`, `await`, `break`,
  `continue`, `nonlocal`. `LET` compiles by α-renaming to plain assignment;
  `TAGBODY` compiles to a state machine, not to mutually tail-calling
  functions (Python has no TCO — the nested-function encoding dies at ~10³
  iterations).
- Do not `(import hyclb.runtime *)` here. It shadows `hy.models.Symbol` with
  the runtime's `Symbol` class and `isinstance` checks then silently fail.

**runtime.py** — CL values on Python. `NIL` is an interned symbol distinct
from `None` and `False`; every conditional compiles through `truthy`. Numeric
predicates return `T`/`NIL`, never Python booleans — returning `False` reads
as *true* under CL's rule and every loop exits immediately with a plausible
zero.

**bridge.lisp** — the SBCL side: readtables, the walker, gensym renaming, the
Maxima bridge, compile-time spec testing, and `defsum`. It runs inside SBCL,
so it can do anything Common Lisp can: Maxima runs there, and so does the
function currently being compiled.

## Things that bite

**Argument evaluation order.** CL guarantees left to right; hoisting a
statement-compiled argument above a call breaks it. `_ordered_call` binds
preceding arguments to temporaries when a later one assigns. Special operators
are exempt — binding `SETQ`'s first argument destroys the assignment target.

**Names both languages define.** A CL name that Python also defines (`map`,
`list`, `print`, `round`, `format`) resolves to whichever table is consulted
first. This is a standing hazard, not a fixed bug; `frompy` handles the
reverse direction by routing Python builtins through `builtins`.

**Caches.** Compiled `.lisp` files are cached as bytecode, and Numba caches
machine code. Both key on a hash of hyclb's own sources (`loader.py`,
`runtime._numba_cache_dir`) so that editing the translator invalidates them.
If you add a file to `hyclb/` that affects translation, make sure it is
covered by that hash.

**Dependency detection.** Decide availability by importing, not by
`find_spec`: a package whose own dependencies are missing has a spec but does
not import, and suites then fail where they should skip.

## Tests

Suites are Common Lisp files in `tests/` that print `(pass ...)` or
`(FAIL ...)`; `test_suites.py` turns that into pytest results and skips a
suite whose dependency (Maxima, Quicklisp, numpy, torch) is absent — the
`NEEDS` table there is what to extend when adding a suite. Each suite doubles
as documentation, so write them to be read.

`test_frompy.py` round-trips Python: run as Python, translate, compile back,
compare output — the program is its own oracle. `test_frompy_stdlib.py` does
the same to ten standard-library modules against CPython. Both are the right
model for new work: check against an independent implementation rather than
against an expectation.

Expected results: bare install (Hy and SBCL only) 46 pass / 5 skip; with numpy
and numba 49 / 2; with torch and lightning all 51.

## Conventions

`.travis.yml` is a leftover from 2020 and is not used; CI is
`.github/workflows/test.yml`.

Comments explain *why*, especially where a simpler-looking implementation is
wrong — most of the subtle code here exists because the obvious version failed
silently. Preserve that reasoning when editing.
