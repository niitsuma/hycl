(import [nose.tools [eq_  assert-equal assert-not-equal]])


(import  [hyclb.core [*]])
(require [hyclb.core [*]])

(import   [hyclb.cl4hy [*]])
(require  [hyclb.cl4hy [*]])

(defn test-load []

  ;;(eval-and-compile
  (load/cl "tests/simple.lisp")
   ;; )
  ;; (eval-and-compile
  ;;   (eval '(defun testfn (x y) (setq y (* x Y)) (+ x y)) )
  ;;   (eval '(defun testfn2 (x y) (setq y (+ x Y)) (* x y))  )
  ;;   )
  ;; (defun testfn (x y) (setq y (* x Y)) (+ x y))
  ;; (defun testfn2 (x y) (setq y (+ x Y)) (* x y))

  ;;;;fail scope ?
  (eq_
    (testfn 3 4) ;;NameError: name 'testfn' is not defined
    15)    

  (eq_
    (testfn2 3 4) ;;NameError: name 'testfn2' is not defined
    21)
  )

