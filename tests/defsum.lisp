;;;; Summed-area tables derived from the sum itself.
;;;;
;;;; DEFSUM's source form is the specification: a nested sum over boxes from
;;;; the origin.  The O(n^N)-build / O(2^N)-query implementation is not
;;;; pattern-matched out of a loop, as an optimizing translator would have to;
;;;; it is derived, by telescoping the sum symbolically in Maxima, and the
;;;; generated code is checked against the naive sum in SBCL before it is
;;;; accepted.  What arrives here has already survived both.

(py-import numpy)

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(defmacro defclose (name expected form)
  `(let ((got ,form))
     (if (< (abs (- got ,expected)) 1e-6) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; --- rank 1: prefix sums ---------------------------------------------

(defsum psum ((k i n)) (aref v k) :element-type integer)

(defvar *v1* (numpy.array (list 3 1 4 1 5 9 2 6)))
(defvar *s1* (psum-build *v1* (py-call numpy.zeros 8 :dtype numpy.int64) 8))

(deftest rank1-full 31 (psum-query *s1* 8 0 7))
(deftest rank1-box 19 (psum-query *s1* 8 2 5))
(deftest rank1-single 9 (psum-query *s1* 8 5 5))
(deftest rank1-matches-naive t
  (let ((ok t))
    (dotimes (a 8)
      (dotimes (w (- 8 a))
        (let ((b (+ a w)))
          (unless (= (psum-query *s1* 8 a b) (psum-naive *v1* a b))
            (setq ok nil)))))
    ok))

;;; --- rank 1 with a weighted summand ----------------------------------

(defsum wsum ((k i n)) (* k (aref v k)) :element-type integer)

(defvar *sw* (wsum-build *v1* (py-call numpy.zeros 8 :dtype numpy.int64) 8))
;; sum of k*v[k] over 2..4 = 2*4 + 3*1 + 4*5 = 31
(deftest weighted-box 31 (wsum-query *sw* 8 2 4))

;;; --- rank 2: the integral image --------------------------------------

(defsum boxsum ((k i n) (l j m)) (aref v k l) :element-type double-float)

(defvar *n* 12)
(defvar *m* 9)
(defvar *v2*
  ;; deterministic pseudo-random data, so nothing here depends on a seed API
  (let ((rows nil) (x 7))
    (dotimes (i *n*)
      (let ((row nil))
        (dotimes (j *m*)
          (setq x (mod (+ (* x 1103515245) 12345) 2147483648))
          (push (/ (float (mod x 1000)) 100.0) row))
        (push (numpy.array (reverse row)) rows)))
    (numpy.array (reverse rows))))
(defvar *s2* (boxsum-build *v2* (numpy.zeros (* *n* *m*)) *n* *m*))

(defclose rank2-full
  (boxsum-naive *v2* 0 (- *n* 1) 0 (- *m* 1))
  (boxsum-query *s2* *n* *m* 0 (- *n* 1) 0 (- *m* 1)))
(defclose rank2-inner
  (boxsum-naive *v2* 3 8 2 6)
  (boxsum-query *s2* *n* *m* 3 8 2 6))
(defclose rank2-edge
  (boxsum-naive *v2* 0 0 0 8)
  (boxsum-query *s2* *n* *m* 0 0 0 8))
(defclose rank2-cell
  (boxsum-naive *v2* 5 5 4 4)
  (boxsum-query *s2* *n* *m* 5 5 4 4))

;;; --- rank 2 with a product summand -----------------------------------
;;; the same machinery, a different sum: sum of v[k,l]*w[k,l] over boxes,
;;; which is what a local cross-correlation needs

(defsum prodsum ((k i n) (l j m)) (* (aref v k l) (aref w k l))
  :element-type double-float)

(defvar *w2* (numpy.add *v2* 1.0))
(defvar *sp* (prodsum-build *v2* *w2* (numpy.zeros (* *n* *m*)) *n* *m*))

(defclose product-box
  (prodsum-naive *v2* *w2* 2 9 1 7)
  (prodsum-query *sp* *n* *m* 2 9 1 7))
