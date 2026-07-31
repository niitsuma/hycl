;;;; Calling a Scm2Cpp kernel from Common Lisp.
;;;;
;;;; Scm2Cpp translates Scheme to C++; with -M it also emits an extern "C"
;;;; wrapper and a ctypes loader, so the translated functions can be called
;;;; from Python on numpy arrays.  Anything callable from Python is callable
;;;; from here without a bridge -- that is the whole point of compiling to
;;;; Python rather than interoperating with it -- so a Scheme-derived C++
;;;; kernel becomes an ordinary Lisp function.
;;;;
;;;; The interesting part is not that it works but what it costs.  The same
;;;; algorithm is available three ways in one program: the C++ kernel through
;;;; ctypes, hyclb's own (optimize (speed 3)) compilation through Numba, and
;;;; the ordinary compilation.  They are put side by side below, and their
;;;; answers must agree.
;;;;
;;;; Set HYCLB_SCM2CPP_PY to the loader -M generated.  See examples/README.md
;;;; for how to produce it.

(py-import numpy)

;;; --- the foreign kernel ----------------------------------------------
;;;
;;; -M writes a ctypes loader beside the library, so there is nothing to
;;; declare here: the generated module is imported and its functions are
;;; called.  It makes each array contiguous and float64 on the way in and
;;; mutates it in place, so BETA and RESID come back written.

(py-import importlib.util)
(py-import os)

(defun load-scm2cpp (loader-path)
  "Import the module -M generated, from wherever it was built."
  (let* ((spec (importlib.util.spec-from-file-location "scm2cpp_kernel"
                                                       loader-path))
         (kernel (importlib.util.module-from-spec spec)))
    (py-call (py-attr (py-attr spec "loader") "exec_module") kernel)
    kernel))

(defun lasso-scm2cpp (kernel x beta resid xnorm lam iters n p)
  (py-call (py-attr kernel "lasso") x beta resid xnorm lam iters n p)
  beta)

;;; --- the same algorithm, compiled by hyclb ---------------------------

(defun soft-threshold (z g)
  (declare (type double-float z g) (optimize (speed 3) (safety 0)))
  (cond ((> z g) (- z g))
        ((< z (- 0.0 g)) (+ z g))
        (t 0.0)))

(defun lasso-hyclb (x beta resid xnorm lam iters n p)
  (declare (type integer iters n p) (type double-float lam)
           (optimize (speed 3) (safety 0) (float-accuracy 0)))
  (dotimes (sweep iters)
    (dotimes (j p)
      (let ((rho 0.0) (old (aref beta j)))
        (dotimes (i n)
          (setq rho (+ rho (* (aref x (+ (* j n) i)) (aref resid i)))))
        (setq rho (+ rho (* old (aref xnorm j))))
        (let ((bnew (/ (soft-threshold rho (* lam n)) (aref xnorm j))))
          (setf (aref beta j) bnew)
          (dotimes (i n)
            (setf (aref resid i)
                  (- (aref resid i)
                     (* (aref x (+ (* j n) i)) (- bnew old)))))))))
  beta)

;;; --- a problem both can be given -------------------------------------

(defun make-problem (n p)
  "A deterministic design matrix, column major and flat, as both kernels index it."
  (let* ((rng (numpy.random.default-rng 12345))
         (x (numpy.ascontiguousarray
             (py-method rng "standard_normal" (py-tuple (list (* n p))))))
         (y (numpy.add
             (numpy.add (numpy.multiply 3.0 (py-getitem x (py-slice 0 n)))
                        (numpy.multiply -2.0 (py-getitem x (py-slice n (* 2 n)))))
             (numpy.multiply
              0.1 (py-method rng "standard_normal" (py-tuple (list n)))))))
    (list x y)))

(defun column-norms (x n p)
  (let ((xnorm (numpy.zeros p)))
    (dotimes (j p)
      (let ((acc 0.0))
        (dotimes (i n)
          (setq acc (+ acc (* (aref x (+ (* j n) i)) (aref x (+ (* j n) i))))))
        (setf (aref xnorm j) acc)))
    xnorm))

(defun run-arm (fn x y xnorm lam iters n p)
  "Fresh state each time: beta starts at zero, so the residual starts at y."
  (funcall fn x (numpy.zeros p) (numpy.copy y) xnorm lam iters n p))

(defun max-abs-diff (a b)
  (py-call float (py-method (numpy.abs (numpy.subtract a b)) "max")))

;;; --- side by side -----------------------------------------------------

(defun main ()
  (let* ((n 2000) (p 200) (lam 0.01) (iters 20)
         (problem (make-problem n p))
         (x (first problem))
         (y (second problem))
         (xnorm (column-norms x n p))
         (lib (py-call os.environ.get "HYCLB_SCM2CPP_PY")))
    (let ((mine (run-arm (function lasso-hyclb) x y xnorm lam iters n p)))
      (print (list 'hyclb-first-coefficients
                   (py-call float (aref mine 0))
                   (py-call float (aref mine 1))))
      (if (py-truthy lib)
          (let* ((kernel (load-scm2cpp lib))
                 (theirs (run-arm (lambda (x beta resid xnorm lam iters n p)
                                    (lasso-scm2cpp kernel x beta resid xnorm
                                                   lam iters n p))
                                  x y xnorm lam iters n p)))
            (print (list 'scm2cpp-first-coefficients
                         (py-call float (aref theirs 0))
                         (py-call float (aref theirs 1))))
            (print (list 'max-abs-difference (max-abs-diff mine theirs)))
            (print (list 'agree (if (< (max-abs-diff mine theirs) 1e-12)
                                    'yes 'no))))
          (print (list 'skipped
                       "set HYCLB_SCM2CPP_PY to the loader -M generated"))))))

;;; --- what each costs --------------------------------------------------

(py-import time)

(defun best-of (thunk reps)
  "The best of REPS runs; a loaded machine makes the mean meaningless."
  (funcall thunk)
  (let ((best 1e18))
    (dotimes (r reps)
      (let ((t0 (time.perf-counter)))
        (funcall thunk)
        (let ((dt (- (time.perf-counter) t0)))
          (when (< dt best) (setq best dt)))))
    best))

(defun timings (n p iters reps)
  (let* ((lam 0.01)
         (problem (make-problem n p))
         (x (first problem))
         (y (second problem))
         (xnorm (column-norms x n p))
         (lib (py-call os.environ.get "HYCLB_SCM2CPP_PY")))
    (print (list 'size n p 'sweeps iters))
    (print (list 'hyclb-speed3-ms
                 (* 1000.0 (best-of (lambda ()
                                      (run-arm (function lasso-hyclb)
                                               x y xnorm lam iters n p))
                                    reps))))
    (when (py-truthy lib)
      (let ((kernel (load-scm2cpp lib)))
        (print (list 'scm2cpp-cpp-ms
                     (* 1000.0
                        (best-of (lambda ()
                                   (run-arm
                                    (lambda (x beta resid xnorm lam iters n p)
                                      (lasso-scm2cpp kernel x beta resid xnorm
                                                     lam iters n p))
                                    x y xnorm lam iters n p))
                                 reps))))))))
