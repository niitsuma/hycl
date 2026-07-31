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
| `tfs_lasso.lisp` | Scm2Cpp's temporal-feature-selection example — moving averages over every window length, LASSO picking the two that matter — written in Common Lisp, agreeing with the C++ coefficient for coefficient |
| `scm2cpp_interop.lisp` | a Scheme kernel compiled to C++ by Scm2Cpp, called from Lisp through ctypes and checked against hyclb's own compilation of the same algorithm |
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


## Calling a Scm2Cpp kernel (`scm2cpp_interop.lisp`)

[Scm2Cpp](https://github.com/niitsuma/scm2cpp) translates Scheme to C++, and
with `-M` also emits an `extern "C"` wrapper and a ctypes loader, so the
translated functions can be called from Python on numpy arrays. Anything
callable from Python is callable from hyclb without a bridge, which is the
practical consequence of compiling *to* Python rather than interoperating
with it.

Scm2Cpp bundles its own cKanren, so no setup is needed beyond the checkout:

```console
$ git clone https://github.com/niitsuma/scm2cpp
$ cd scm2cpp && raco link --user vendor/cKanren   # or just ./run-tests.sh
$ racket scm2cpp-file.scm -t scm2c.typ -M lasso.scm
```

`-M` writes `lasso_capi.cpp` and `lasso.py` beside the usual pair. It wraps
every function whose signature crosses the C ABI and names the rest rather
than dropping them silently; a kernel taking its arrays as parameters comes
out a template, so one line instantiating it is added by hand:

```cpp
#include "lasso_capi.cpp"
extern "C" int scm2cpp_lasso(double *x, double *beta, double *resid,
                             double *xnorm, double lam, int iters, int n, int p)
{ return lasso<double *, double *, double *, double *>(
      x, beta, resid, xnorm, lam, iters, n, p); }
```

```console
$ g++ -O2 -std=c++11 -shared -fPIC -I. -I/path/to/scm2cpp.hpp-lib \
      -include boost/operators.hpp -include boost/optional.hpp \
      -o liblasso.so wrap.cpp
$ HYCLB_SCM2CPP_LIB=$PWD/liblasso.so python -c \
    "from hyclb.api import cl_load, new_module; \
     m = new_module('x'); cl_load('examples/scm2cpp_interop.lisp', m); m.main()"
```

Without the variable the example still runs and reports that the foreign arm
was skipped. `main` checks that the two arms agree; `timings` puts them side
by side.


## The same computation, two compilers (`tfs_lasso.lisp`)

Scm2Cpp's `examples/tfs-lasso.scm` builds a synthetic time series, offers
every moving-average window from 1 to 40 as a candidate feature, and lets
LASSO coordinate descent find the two window lengths the signal was actually
built from. `tfs_lasso.lisp` is the same computation in Common Lisp: the same
Park–Miller generator with the same seed, the same windows, the same penalty,
the same 20{,}000 sweeps. The data is therefore identical rather than merely
similar, and the answers have to match.

```console
$ python -c "from hyclb.api import cl_load, new_module; \
    m = new_module('t'); cl_load('examples/tfs_lasso.lisp', m); m.main()"
```

Both find `w=5` and `w=20`, and agree on every printed digit:

| | w=5 | w=20 | max abs beta among the other 38 | max abs y − yhat |
| --- | --- | --- | --- | --- |
| Scm2Cpp (C++, `-I x`) | 1.96512 | −1.45172 | 0.0072154 | 0.0997609 |
| hyclb | 1.9651159 | −1.4517178 | 0.0072154 | 0.0997609 |

`compare` runs both solvers in one process on one design matrix, so the
comparison is of two compilations of one algorithm rather than of two
programs; `timings` breaks the hyclb side into its phases. Point
`HYCLB_SCM2CPP_LIB` at the shared library as for `scm2cpp_interop.lisp`.

The prefix sums are worth a look. Scm2Cpp reaches the summed-area table by
*recognising* the naive O(n²) nest (`-I x`); hyclb reaches the same table by
*deriving* it from the sum written as a specification (`defsum`, see
`tests/defsum.lisp`). Both arms are in the example.
