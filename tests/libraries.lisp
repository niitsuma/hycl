(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))
(ql:quickload "metabang-bind")
(deftest bind-nested 6
  (metabang.bind:bind (((a (b c)) '(1 (2 3)))) (+ a b c)))
(deftest bind-flat 3
  (metabang.bind:bind ((x 1) (y 2)) (+ x y)))
(ql:quickload "let-over-lambda")

;; defmacro! evaluates an o! argument exactly once
(lol:defmacro! square-once (o!x)
  `(* ,g!x ,g!x))

(defun counted ()
  (let ((n 0))
    (square-once (progn (setq n (+ n 1)) 3))
    n))
(deftest defmacro-bang-once 1 (counted))
(deftest defmacro-bang-value 9 (square-once 3))
