;;;; Specifications checked while the program is compiled.
;;;;
;;;; A SPEC declaration says what a function may be given, what it returns and
;;;; how the two are related.  Because the expander is a live Common Lisp, the
;;;; function can be run there: a counterexample stops the build before any
;;;; Python exists.  How much is checked at run time is the SAFETY level.

(declaim (declaration spec))

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; --- contracts checked at run time ------------------------------------

(defun safe-half (n)
  (declare (type integer n)
           (spec :args (evenp n)
                 :ret  (integerp ret)
                 :fn   (= n (* 2 ret))
                 :test 200)
           (optimize (safety 3)))
  (/ n 2))

(deftest spec-accepts 21 (safe-half 42))
(deftest spec-rejects-bad-args 'caught
  (handler-case (safe-half 43) (error (e) 'caught)))

;;; --- the relation is what types cannot say ----------------------------

(defun insert-first (x lst)
  (declare (type integer x) (type list lst)
           (spec :ret (listp ret)
                 :fn  (= (length ret) (1+ (length lst)))
                 :test 200)
           (optimize (safety 3)))
  (cons x lst))

(deftest spec-relation '(9 1 2) (insert-first 9 '(1 2)))

;;; --- safety 0 compiles the checks away --------------------------------

(defun unchecked-half (n)
  (declare (type integer n)
           (spec :args (evenp n))
           (optimize (speed 3) (safety 0)))
  (// n 2))

;; the contract is not enforced here, exactly as (safety 0) licenses
(deftest safety-zero-unchecked 21 (unchecked-half 43))
