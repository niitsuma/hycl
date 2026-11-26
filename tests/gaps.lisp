;;;; Functions and forms that were missing or broke, found on the way.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; SEARCH
(deftest search-in-a-string 6 (search "lo" "hello lo"  :start2 4))
(deftest search-finds-the-first 3 (search "lo" "hello lo"))
(deftest search-from-the-end 6 (search "lo" "hello lo" :from-end t))
(deftest search-misses nil (search "xy" "hello"))
(deftest search-in-a-list 1 (search '(2 3) '(1 2 3 4)))
(deftest search-with-a-test 0 (search "HE" "hello" :test #'char-equal))

;;; COERCE
(deftest coerce-to-a-double 3.0 (coerce 3 'double-float))
(deftest coerce-to-a-list '(1 2 3) (coerce (vector 1 2 3) 'list))
(deftest coerce-a-string-to-a-list 3 (length (coerce "abc" 'list)))
(deftest coerce-to-a-vector 2 (aref (coerce '(1 2 3) 'vector) 1))
(deftest coerce-to-a-string "abc" (coerce (coerce "abc" 'list) 'string))
(deftest coerce-a-ratio 0.5 (coerce 1/2 'float))

;;; DEFINE-MODIFY-MACRO used to kill the expander
(define-modify-macro mulf (factor) *)
(defvar *scaled* 3)
(mulf *scaled* 4)
(deftest a-modify-macro-on-a-variable 12 *scaled*)
(defun scale-first (v) (let ((a (list 1 2))) (mulf (car a) v) a))
(deftest a-modify-macro-on-a-place '(5 2) (scale-first 5))

;;; DEFTYPE is the expander's: a declaration may then use the name
(deftype small () '(integer 0 9))
(defun small-sum (a b) (declare (type small a b)) (+ a b))
(deftest a-declared-deftype 7 (small-sum 3 4))

;;; REST
(deftest rest-is-cdr '(2 3) (rest '(1 2 3)))
(deftest rest-as-a-value '((2) (4)) (mapcar #'rest '((1 2) (3 4))))

;;; /= compares numbers, pair by pair: a NaN differs from itself
(defvar *nan* (py-call float "nan"))
(deftest nan-differs-from-itself t (/= *nan* *nan*))
(deftest not-equal-of-three '(t nil) (list (/= 1 2 3) (/= 1 2 1)))
(deftest an-integer-equals-its-float nil (/= 1 1.0))
