# Measured speeds

All figures below were taken on an idle machine — a 20-core Intel i9-10900X
and an RTX 4090 — with the one-minute load average below 4 and the GPU below
10% for three consecutive minutes before starting, and the load watched
throughout: peak 3.16 against a threshold of 4. Times are the best of five
runs after a warm-up. Every arm of every comparison computes the same answer,
verified per run and reported with each table.

Raw output: `results/all-idle.txt`, `results/tfs-idle.txt`.

## 1. What the declaration is worth

A Leibniz series of 2×10⁶ terms — a loop with real work per iteration, which
an optimiser cannot fold away. One source text, two compilations.

| Compilation | Time | vs. hand-written Python |
| --- | ---: | ---: |
| hyclb, ordinary (Lisp value representation) | 3,830 ms | 0.07× |
| hyclb, `(optimize (speed 3))` | **2.6 ms** | **105×** |
| hand-written Python | 273 ms | 1× |

The ordinary compilation is 14× slower than the equivalent Python — `NIL`
tests, predicates returning symbols, no inlining. The declared one is 105×
faster, because it is no longer Python. The difference between the two rows
is one `declare` form.

## 2. LASSO coordinate descent

Twenty sweeps, `tol=0` so the library solvers cannot stop early. CPU arms
pinned to one thread. All arms agree to 9×10⁻¹⁶.

| | 500×50 | 2000×200 | 10⁴×500 | 2·10⁵×200 |
| --- | ---: | ---: | ---: | ---: |
| hyclb, ordinary compilation | 2,315 ms | — | — | — |
| hyclb, `(speed 3)` | 1.1 ms | 18.6 ms | 266 ms | 2,412 ms |
| hyclb, + `(float-accuracy 0)` | **0.7 ms** | 10.6 ms | **183 ms** | **1,967 ms** |
| NumPy, vectorised inner loop | 6.2 ms | 33.3 ms | 245 ms | 2,417 ms |
| scikit-learn (Cython, CPU) | 1.1 ms | **9.1 ms** | 247 ms | 2,513 ms |
| cuML (GPU, data on device) | 61.0 ms | 241 ms | 691 ms | 238 ms |
| hand-written cooperative CUDA | — | 23.0 ms | 71.5 ms | **103 ms** |

- The declaration is again the whole difference: **2,134×** between the two
  hyclb rows at the smallest size, from the same source.
- `(float-accuracy 0)` is worth a further **1.2–1.8×**; the inner-loop
  reduction is the shape that vectorises once reassociation is allowed.
- Against scikit-learn's hand-tuned Cython kernel the Lisp is level or
  ahead everywhere except 2000×200.
- cuML is **56× slower than the CPU** at 500×50 and only overtakes at
  2·10⁵×200.

## 3. The GPU is not one thing

The same arithmetic on the same RTX 4090, differing only in where the
synchronisation goes. Coordinate descent is *p* sequential reductions of
length *n* per sweep, so what matters is how often the host is involved.

| n×p | per-coordinate launches | one launch, grid barriers | cuML | CPU |
| --- | ---: | ---: | ---: | ---: |
| 2000×200 | 6,910 ms † | 23.0 ms | 241 ms | **8.3 ms** |
| 10⁴×500 | — | **71.5 ms** | 646 ms | 178 ms |
| 2·10⁵×200 | 7,735 ms † | **103 ms** | 250 ms | 2,011 ms |

† measured under load; the shape of the result, not its precision, is the
point — an empty kernel launch cost 517 µs there.

Keeping the sweep loop on the device beats cuML by **2.8–10×** and the best
CPU arm by **20×** at the largest size. Launching per coordinate is
**300× worse** than launching once.

### OpenACC reaches neither

OpenACC has no barrier across gangs, so the synchronisation has only two
places to go, and both are bad here (n=2000, p=200, 20 sweeps):

| | Time | |
| --- | ---: | --- |
| host CPU, same C code | 132 ms | |
| `acc parallel` per coordinate | 147,053 ms | 8,000 launches |
| `acc parallel num_gangs(1)` | 3,034 ms | 1 launch, 1 of 128 SMs |

Directive-based offload can express few launches *or* wide parallelism here,
not both. The fast form is a whole-algorithm transformation, not a loop
rewrite.

## 4. Against C++ from the same algorithm

Scm2Cpp's temporal-feature-selection example — moving averages over every
window length from 1 to 40, LASSO recovering the two the signal was built
from — written in Common Lisp with the same generator, seed, windows,
penalty and 20,000 sweeps. Both solvers run in one process on one design
matrix, so this compares two compilations of one algorithm rather than two
programs.

| | Time |
| --- | ---: |
| hyclb, `(speed 3) (float-accuracy 0)` | **409 ms** |
| Scm2Cpp → C++, `g++ -O2` | 628 ms |

Coefficient vectors differ by 7.3×10⁻¹⁵. The plain LASSO kernel shows the
same relation: hyclb 39.5 ms against 46.3 ms at 2000×200, and 817 ms against
1,085 ms at 10⁴×500. Neither is fast because of its language; both compile
the same scalar arithmetic, and LLVM and GCC differ by rather less than the
choice of algorithm does.

## 5. Prefix sums: recognised against derived

| | Time |
| --- | ---: |
| naive O(n²) nest | 0.0699 ms |
| summed-area table | **0.0015 ms** |

46×. The interesting part is not the ratio but how each system gets there:
Scm2Cpp **recognises** the naive loop and rewrites it (`-I x`); hyclb
**derives** the recurrence by telescoping the sum in Maxima, from the
specification rather than from an implementation (`defsum`).

## 6. Lazy stream against compiled kernel

| | Per term |
| --- | ---: |
| compiled loop, `(speed 3)` | **1.9 ns** |
| lazy stream | 2,168 ns |

1,157×. The division of labour is forced by what Numba can compile: a stream
is a cons whose tail is a closure, which it cannot; the term function is
arithmetic, which it can. Neither number makes the other redundant — the
stream is for looking at a sequence, the loop for exhausting one.

An earlier version of this measurement compared against a loop summing
*i*²+1, which LLVM folds to a closed form; the compiled arm came out at
0.2 ns per term, meaning the loop had been optimised away entirely and the
ratio measured nothing. The term above is a multiplicative hash reduced
modulo a prime, which cannot be folded.

## 7. Build time against run time

For a function containing a 10⁶-iteration loop:

| Phase | Time |
| --- | ---: |
| expand and translate (the only phase involving SBCL) | 0.7 ms |
| Hy compilation and definition | 14 ms |
| execution, declared for speed | below measurement resolution |

Building the module dominates running it. Compilation goes through Python's
ordinary source-file machinery, so the result is cached as bytecode and a
second import needs no SBCL at all — verified with `PATH=/var/empty`.
