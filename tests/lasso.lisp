;;;; LASSO regression by coordinate descent, written twice.
;;;;
;;;; The two definitions have the same body.  One is compiled the ordinary
;;;; way, keeping Common Lisp's value representation; the other declares
;;;; (optimize (speed 3) (safety 0)) and is compiled without it, which is what
;;;; lets Numba turn it into machine code.  The design matrix is stored column
;;;; major in a flat array -- coordinate descent sweeps one column at a time,
;;;; so that is the layout that reads contiguously -- and every access is a
;;;; subscript.

(py-import numpy)

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; --- the ordinary compilation ----------------------------------------

(defun soft-threshold (z g)
  (cond ((> z g) (- z g))
        ((< z (- 0.0 g)) (+ z g))
        (t 0.0)))

(defun lasso-plain (x y beta resid xnorm lam iters n p)
  "Coordinate descent.  RESID is y - X beta, kept up to date."
  (dotimes (sweep iters)
    (dotimes (j p)
      (let ((rho 0.0) (old (aref beta j)))
        (dotimes (i n)
          (setq rho (+ rho (* (aref x (+ (* j n) i)) (aref resid i)))))
        (setq rho (+ rho (* old (aref xnorm j))))
        (let ((new (/ (soft-threshold rho (* lam n)) (aref xnorm j))))
          (setf (aref beta j) new)
          (dotimes (i n)
            (setf (aref resid i)
                  (- (aref resid i) (* (aref x (+ (* j n) i)) (- new old)))))))))
  beta)

;;; --- the same, declared for speed ------------------------------------

(defun soft-threshold-fast (z g)
  (declare (type double-float z g) (optimize (speed 3) (safety 0)))
  (cond ((> z g) (- z g))
        ((< z (- 0.0 g)) (+ z g))
        (t 0.0)))

(defun lasso-fast (x y beta resid xnorm lam iters n p)
  (declare (type integer iters n p) (type double-float lam)
           (optimize (speed 3) (safety 0)))
  (dotimes (sweep iters)
    (dotimes (j p)
      (let ((rho 0.0) (old (aref beta j)))
        (dotimes (i n)
          (setq rho (+ rho (* (aref x (+ (* j n) i)) (aref resid i)))))
        (setq rho (+ rho (* old (aref xnorm j))))
        (let ((new (/ (soft-threshold-fast rho (* lam n)) (aref xnorm j))))
          (setf (aref beta j) new)
          (dotimes (i n)
            (setf (aref resid i)
                  (- (aref resid i) (* (aref x (+ (* j n) i)) (- new old)))))))))
  beta)

;;; --- the same again, permitting reassociation ------------------------

(defun lasso-approx (x y beta resid xnorm lam iters n p)
  (declare (type integer iters n p) (type double-float lam)
           (optimize (speed 3) (safety 0) (float-accuracy 0)))
  (dotimes (sweep iters)
    (dotimes (j p)
      (let ((rho 0.0) (old (aref beta j)))
        (dotimes (i n)
          (setq rho (+ rho (* (aref x (+ (* j n) i)) (aref resid i)))))
        (setq rho (+ rho (* old (aref xnorm j))))
        (let ((new (/ (soft-threshold-fast rho (* lam n)) (aref xnorm j))))
          (setf (aref beta j) new)
          (dotimes (i n)
            (setf (aref resid i)
                  (- (aref resid i) (* (aref x (+ (* j n) i)) (- new old)))))))))
  beta)

;;; --- correctness ------------------------------------------------------
;;; A single feature that predicts y exactly: with a small penalty the
;;; coefficient should come out near 2, shrunk slightly toward zero.

(defun fit-one (lam)
  (let* ((n 4) (p 1)
         (x (numpy.array (list 1.0 2.0 3.0 4.0)))
         (y (numpy.array (list 2.0 4.0 6.0 8.0)))
         (beta (numpy.zeros p))
         (resid (numpy.array (list 2.0 4.0 6.0 8.0)))
         (xnorm (numpy.array (list 30.0))))
    (aref (lasso-fast x y beta resid xnorm lam 50 n p) 0)))

(deftest lasso-unpenalised 'yes
  (if (< (abs (- (fit-one 0.0) 2.0)) 1e-9) 'yes 'no))
(deftest lasso-shrinks 'yes
  (if (< (fit-one 1.0) 2.0) 'yes 'no))
