# Examples

The one self-contained example lives here:

* **`main.py` + `model_math.lisp`** — an ordinary Python program that grew a
  Lisp module. The activation function's backward pass was derived by Maxima
  while the program was compiled, so Torch never builds a tape for it. Run it
  twice with SBCL off the `PATH` the second time; it still works.

Everything else is in `../tests`, because those files assert their results and
so cannot quietly rot. They are written to be read:

| file | what it shows |
| --- | --- |
| `lagrangian.lisp` | a Lagrangian is written down; Maxima derives the equations of motion at compile time; what runs is a numeric integrator |
| `sequences.lisp` | a recurrence is solved symbolically, then becomes both a lazy stream and a machine-code kernel |
| `from_python.py` | an existing Python loop translated into Lisp, then declared fast |
| `defsum.lisp` | write the sum, get the integral image: O(n^4) as specification, O(n^2) as derived implementation |
| `lasso.lisp` | one algorithm, three compilations: what `(optimize (speed 3))` and `(float-accuracy 0)` are each worth |
| `maxima.lisp` | symbolic differentiation performed while the program compiles |
| `maxima-apps.lisp` | analytic gradients replacing a backward pass, common subexpression elimination, series, identity checking |
| `sweep.lisp` | a hyperparameter grid computed at macroexpansion time, driving PyTorch Lightning |
| `lightning_demo.lisp` | a LightningModule whose class definition a macro generates |
| `spec.lisp` | specifications checked while the program is compiled |
| `clos.lisp` | multiple dispatch, which the host language does not have |
| `generators.lisp` | `yield` through every binding and control form |
| `kanren_demo.py` | compiling a Quicklisp library that is not macro-only |

Run one directly:

```
python -c "import hyclb; from hyclb.api import cl_load; cl_load('tests/lagrangian.lisp')"
```
