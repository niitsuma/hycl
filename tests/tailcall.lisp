;;;; Self-tail recursion compiles to a loop.
;;;;
;;;; Python has no tail-call optimisation, so the general encoding of a tail
;;;; call is a stack frame and a deep recursion dies.  A call to the function
;;;; *itself* in tail position is a loop, and the translator rewrites it as
;;;; one.  Mutual recursion is not covered and still uses the stack.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name)) (print (list 'FAIL ',name 'got got)))))

(defun count-down (n acc)
  (if (= n 0) acc (count-down (- n 1) (+ acc n))))

(defun evenp2 (n) (if (= n 0) t (oddp2 (- n 1))))
(defun oddp2 (n) (if (= n 0) nil (evenp2 (- n 1))))

(defun fact (n acc) (if (= n 0) acc (fact (- n 1) (* acc n))))

(defun sum-list (lst acc)
  (let ((x (if (null lst) 0 (car lst))))
    (if (null lst) acc (sum-list (cdr lst) (+ acc x)))))

;; a mutually recursive pair is left alone -- only self calls are rewritten
;; non-tail recursion must be untouched
(defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(deftest deep-self-tail 500000500000 (count-down 1000000 0))
(deftest fact-20 2432902008176640000 (fact 20 1))
(deftest sum-list 15 (sum-list (list 1 2 3 4 5) 0))
(deftest non-tail-untouched 55 (fib 10))
(deftest simultaneous-rebind 500500 (count-down 1000 0))
(deftest mutual-still-works t (evenp2 100))
