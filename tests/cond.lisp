(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(define-condition too-big (error) ((value :initform 0)))

(defun check (n)
  (if (> n 100) (error 'too-big :value n) n))

(deftest handler-ok 5 (handler-case (check 5) (too-big (e) 'caught)))
(deftest handler-catch 'caught (handler-case (check 500) (too-big (e) 'caught)))
(deftest handler-slot 500
  (handler-case (check 500) (too-big (e) (slot-value e 'value))))
(deftest handler-generic 'any
  (handler-case (error "plain failure") (error (e) 'any)))

;; catching what Python raises
(py-import-as builtins bi)
(deftest catch-python 'from-python
  (handler-case (py-call bi.int "not-a-number") (error (e) 'from-python)))

;; and Python catching what Lisp signals is the same object
(deftest condition-is-exception t
  (handler-case (error 'too-big :value 1) (error (e) t)))

;; restarts
(defun risky (n)
  (restart-case (if (> n 10) (invoke-restart 'use-value 0) n)
    (use-value (v) v)))
(deftest restart-normal 3 (risky 3))
(deftest restart-invoked 0 (risky 50))
