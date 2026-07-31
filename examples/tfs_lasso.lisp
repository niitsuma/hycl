;;;; Temporal feature selection: which moving-average window matters?
;;;;
;;;; This is Scm2Cpp's tfs-lasso example, written in Common Lisp and compiled
;;;; by hyclb, so that the same computation can be timed against the same
;;;; computation compiled to C++.  Everything is chosen to match: the same
;;;; Park-Miller generator with the same seed, the same window lengths, the
;;;; same penalty, the same number of sweeps.  The two therefore have to agree
;;;; coefficient for coefficient, and they do.
;;;;
;;;; The problem: y is built from moving averages of x at two window lengths
;;;; (5 and 20) that the solver is not told about.  Every window from 1 to 40
;;;; is offered as a candidate and coordinate descent must find the two.
;;;;
;;;; The prefix sums are built by the naive O(n^2) nest on purpose, because
;;;; that is the form Scm2Cpp's -I rewrites into a summed-area table.  hyclb
;;;; has the same table available and derives it rather than recognising it
;;;; (see tests/defsum.lisp), so the third arm below asks for it by writing
;;;; the sum -- the specification -- instead of the loop.

(py-import numpy)
(py-import time)

;;; --- the same generator, so the data is the same ---------------------

(defun base-series (n seed)
  "Park-Miller through Schrage's method, as the Scheme source writes it.

Every intermediate stays inside 32-bit signed range, which is what makes the
two implementations produce identical data rather than merely similar data."
  (let ((x (numpy.zeros n))
        (s seed))
    (dotimes (k n)
      (let* ((hi (truncate s 127773))
             (lo (mod s 127773))
             (test (- (* 16807 lo) (* 2836 hi))))
        (setq s (if (> test 0) test (+ test 2147483647))))
      (setf (aref x k) (* 10.0 (/ (* 1.0 s) 2147483647.0))))
    x))

;;; --- prefix sums, the naive way, on the fast path --------------------

(defun prefix-naive (x ps n)
  "ps[i] = sum of x[0..i], as O(n^2).  Written the way the Scheme is."
  (declare (type integer n) (optimize (speed 3) (safety 0)))
  (dotimes (i n)
    (let ((acc 0.0))
      (dotimes (a (+ i 1))
        (setq acc (+ acc (aref x a))))
      (setf (aref ps i) acc)))
  ps)

;;; --- prefix sums, derived from the sum rather than written ------------
;;; DEFSUM takes the specification -- the sum itself -- and derives the
;;; recurrence by telescoping it in Maxima, so this arm is O(n) without the
;;; O(n^2) loop ever being written.  Scm2Cpp reaches the same table by
;;; recognising the loop; this reaches it from the sum.

(defsum pre ((k i n)) (aref v k) :element-type double-float)

;;; --- the candidate features ------------------------------------------

(defun moving-averages (ps xd wmax nobs)
  "Every candidate window's moving average: one O(1) query against the table."
  (declare (type integer wmax nobs) (optimize (speed 3) (safety 0)))
  (dotimes (w wmax)
    (dotimes (row nobs)
      (let ((tt (+ wmax row)))
        (setf (aref xd (+ (* w nobs) row))
              (/ (- (aref ps tt) (aref ps (- tt (+ w 1))))
                 (* 1.0 (+ w 1)))))))
  xd)

(defun column-norms (xd xnorm nobs p)
  (declare (type integer nobs p) (optimize (speed 3) (safety 0)))
  (dotimes (j p)
    (let ((s 0.0))
      (dotimes (row nobs)
        (setq s (+ s (* (aref xd (+ (* j nobs) row))
                        (aref xd (+ (* j nobs) row))))))
      (setf (aref xnorm j) s)))
  xnorm)

;;; --- the solver -------------------------------------------------------

(defun soft-threshold (z g)
  (declare (type double-float z g) (optimize (speed 3) (safety 0)))
  (cond ((> z g) (- z g))
        ((< z (- 0.0 g)) (+ z g))
        (t 0.0)))

(defun lasso (x beta resid xnorm lam iters n p)
  (declare (type integer iters n p) (type double-float lam)
           (optimize (speed 3) (safety 0) (float-accuracy 0)))
  (dotimes (sweep iters)
    (dotimes (j p)
      (let ((rho 0.0) (old (aref beta j)))
        (dotimes (i n)
          (setq rho (+ rho (* (aref x (+ (* j n) i)) (aref resid i)))))
        (setq rho (+ rho (* old (aref xnorm j))))
        (let ((bnew (/ (soft-threshold rho (* lam (* 1.0 n))) (aref xnorm j))))
          (setf (aref beta j) bnew)
          (dotimes (i n)
            (setf (aref resid i)
                  (- (aref resid i)
                     (* (aref x (+ (* j n) i)) (- bnew old)))))))))
  beta)

;;; --- putting it together ---------------------------------------------

(defvar *n* 400)
(defvar *wmax* 40)
(defvar *nobs* 360)
(defvar *p* 40)
(defvar *seed* 98765)
(defvar *true-w1* 5)
(defvar *true-b1* 2.0)
(defvar *true-w2* 20)
(defvar *true-b2* -1.5)
(defvar *lam* 0.02)
(defvar *iters* 20000)

(defun build-features (prefix-fn)
  "The design matrix, given a way of computing the prefix sums."
  (let* ((x (base-series *n* *seed*))
         (ps (funcall prefix-fn x))
         (xd (numpy.zeros (* *wmax* *nobs*))))
    (moving-averages ps xd *wmax* *nobs*)))

(defun target (xd)
  (let ((y (numpy.zeros *nobs*)))
    (dotimes (row *nobs*)
      (setf (aref y row)
            (+ (* *true-b1* (aref xd (+ (* (- *true-w1* 1) *nobs*) row)))
               (* *true-b2* (aref xd (+ (* (- *true-w2* 1) *nobs*) row))))))
    y))

(defun solve (xd y)
  (let ((xnorm (column-norms xd (numpy.zeros *p*) *nobs* *p*)))
    (lasso xd (numpy.zeros *p*) (numpy.copy y) xnorm *lam* *iters* *nobs* *p*)))

(defun report (beta xd y)
  (print (list 'selected-windows))
  (dotimes (j *p*)
    (when (> (abs (aref beta j)) 1e-6)
      (print (list 'w (+ j 1) 'beta-hat (py-call float (aref beta j))))))
  (print (list 'at-true-windows
               'w *true-w1* (py-call float (aref beta (- *true-w1* 1)))
               'w *true-w2* (py-call float (aref beta (- *true-w2* 1)))))
  (let ((maxother 0.0) (maxdiff 0.0))
    (dotimes (j *p*)
      (unless (or (= (+ j 1) *true-w1*) (= (+ j 1) *true-w2*))
        (setq maxother (max maxother (abs (aref beta j))))))
    (dotimes (row *nobs*)
      (let ((yhat 0.0))
        (dotimes (j *p*)
          (setq yhat (+ yhat (* (aref beta j) (aref xd (+ (* j *nobs*) row))))))
        (setq maxdiff (max maxdiff (abs (- (aref y row) yhat))))))
    (print (list 'max-abs-beta-among-the-other-38 (py-call float maxother)))
    (print (list 'max-abs-y-minus-yhat (py-call float maxdiff)))))

(defun main ()
  (let* ((xd (build-features (lambda (x)
                               (prefix-naive x (numpy.zeros *n*) *n*))))
         (y (target xd)))
    (report (solve xd y) xd y)))

;;; --- timing -----------------------------------------------------------

(defun best-of (thunk reps)
  (funcall thunk)
  (let ((best 1e18))
    (dotimes (r reps)
      (let ((t0 (time.perf-counter)))
        (funcall thunk)
        (let ((dt (- (time.perf-counter) t0)))
          (when (< dt best) (setq best dt)))))
    best))

(defun timings (reps)
  "The three phases, separately, so the comparison says where the time goes."
  (let* ((x (base-series *n* *seed*))
         (xd (build-features (lambda (x)
                               (prefix-naive x (numpy.zeros *n*) *n*))))
         (y (target xd)))
    (print (list 'prefix-naive-on2-ms
                 (* 1000.0 (best-of (lambda ()
                                      (prefix-naive x (numpy.zeros *n*) *n*))
                                    reps))))
    (print (list 'prefix-derived-table-ms
                 (* 1000.0 (best-of (lambda ()
                                      (pre-build x (numpy.zeros *n*) *n*))
                                    reps))))
    (print (list 'lasso-ms
                 (* 1000.0 (best-of (lambda () (solve xd y)) reps))))
    (print (list 'whole-ms
                 (* 1000.0 (best-of (lambda () (main-quiet)) reps))))))

(defun main-quiet ()
  (let* ((xd (build-features (lambda (x)
                               (prefix-naive x (numpy.zeros *n*) *n*))))
         (y (target xd)))
    (solve xd y)))

;;; --- against the C++ the same program compiles to --------------------
;;; Scm2Cpp's tfs-lasso.scm is this computation in Scheme.  Point
;;; HYCLB_SCM2CPP_LIB at the shared library built from it (see
;;; examples/README.md) and the two solvers are run on the same data, so the
;;; comparison is of two compilations of one algorithm rather than of two
;;; programs.

(py-import ctypes)
(py-import os)

(defun load-scm2cpp (path)
  (let* ((lib (py-call ctypes.CDLL path))
         (fn (py-attr lib "scm2cpp_lasso"))
         (ptr (py-call ctypes.POINTER ctypes.c-double)))
    (py-set-attr fn "argtypes"
                 (py-list (list ptr ptr ptr ptr ctypes.c-double
                                ctypes.c-int ctypes.c-int ctypes.c-int)))
    (py-set-attr fn "restype" ctypes.c-int)
    fn))

(defun as-ptr (a)
  (py-method (py-attr a "ctypes") "data_as"
             (py-call ctypes.POINTER ctypes.c-double)))

(defun solve-cpp (fn xd y)
  (let ((xnorm (column-norms xd (numpy.zeros *p*) *nobs* *p*))
        (beta (numpy.zeros *p*))
        (resid (numpy.copy y)))
    (py-call fn (as-ptr xd) (as-ptr beta) (as-ptr resid) (as-ptr xnorm)
             *lam* *iters* *nobs* *p*)
    beta))

(defun compare (reps)
  (let* ((xd (build-features (lambda (x)
                               (prefix-naive x (numpy.zeros *n*) *n*))))
         (y (target xd))
         (lib (py-call os.environ.get "HYCLB_SCM2CPP_LIB"))
         (mine (solve xd y)))
    (print (list 'hyclb-ms
                 (* 1000.0 (best-of (lambda () (solve xd y)) reps))))
    (if (py-truthy lib)
        (let* ((fn (load-scm2cpp lib))
               (theirs (solve-cpp fn xd y)))
          (print (list 'scm2cpp-cpp-ms
                       (* 1000.0 (best-of (lambda () (solve-cpp fn xd y))
                                          reps))))
          (print (list 'max-abs-difference
                       (py-call float
                                (py-method (numpy.abs (numpy.subtract mine theirs))
                                           "max"))))
          (print (list 'agree
                       (if (< (py-call float
                                       (py-method (numpy.abs
                                                   (numpy.subtract mine theirs))
                                                  "max"))
                              1e-12)
                           'yes 'no))))
        (print (list 'skipped "set HYCLB_SCM2CPP_LIB")))))
