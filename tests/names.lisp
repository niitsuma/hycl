;;;; A variable may have the name of a function.
;;;;
;;;; Common Lisp keeps variables and functions apart; Python does not, and a
;;;; bare symbol that names a runtime function is that function in the
;;;; compiled program.  So a name bound by LET, a lambda list, DOLIST and the
;;;; rest has to be read as the variable inside its scope, while a call of
;;;; the same name is still the function.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(defun span-of (xs)
  (let ((first (aref xs 0)) (last (aref xs 2)))
    (- last first)))
(deftest let-binds-a-function-name 8 (span-of (vector 1 5 9)))

;; the parameter and the function, side by side
(defun pick (first rest) (if (> first 0) first (first rest)))
(deftest a-parameter-and-a-call '(7 3) (list (pick 0 '(7 8)) (pick 3 '(7 8))))

(defun sum-list (list)
  (let ((count 0))
    (dolist (max list) (incf count max))
    count))
(deftest dolist-and-a-parameter 6 (sum-list '(1 2 3)))

(defun triangle (length)
  (let ((second 0))
    (dotimes (reverse length) (setf second (+ second reverse)))
    second))
(deftest dotimes-and-setf 10 (triangle 5))

(deftest a-lambda-parameter 8 (funcall (lambda (length) (* 2 length)) 4))
(deftest let-star '(1 2) (let* ((car 1) (cdr (+ car 1))) (list car cdr)))
(deftest multiple-value-bind '(1 2)
  (multiple-value-bind (min max) (values 1 2) (list min max)))
(deftest destructuring-bind '(1 (2 3))
  (destructuring-bind (first &rest rest) '(1 2 3) (list first rest)))
(deftest an-optional-parameter '(1 5)
  (funcall (lambda (first &optional (second 5)) (list first second)) 1))

;; outside any binding the bare name is still the function, as before
(deftest unbound-it-is-the-function '(1 3) (mapcar first '((1 2) (3 4))))
;; and the binding ends with its form
(deftest the-scope-ends '(9 1)
  (list (let ((first 9)) first) (funcall first '(1 2))))
