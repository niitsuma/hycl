(import [nose.tools [eq_  assert-equal assert-not-equal]])


(import  [hyclb.core [*]])
(require [hyclb.core [*]])

(import  [hyclb.cl4hy [*]])


(defn test-eval-str []
  
  (setv clisp (Clisp))
  (eq_
    (clisp.eval_str "(+ 2 5)")
    7)
  (clisp.eval_str "(defmacro alpha (x y) `(beta ,x ,y)) ")
  
  (eq_
    (clisp.eval_str "(macroexpand '(alpha a b))")
    '(BETA A B)
    )

  
  )

(defn test-eval-qexpr []
  
  (setv clisp (Clisp))
  (eq_
    (clisp.eval_qexpr '(+ 2 5))
    7)
  
  (clisp.eval_qexpr '(defmacro alpha (x y) `(beta ,x ,y)) )
  
  (eq_
    (clisp.eval_qexpr '(macroexpand '(alpha a b)))
    '(BETA A B)
    )
  
  )

(defn test-quicklisp []
  (setv clisp (Clisp :quicklisp True))
  (clisp.eval_qexpr  '(ql:quickload "alexandria"))
  (eq_
    (clisp.eval_str  "(alexandria:destructuring-case '(:x 0 1 2)   ((:x x y z) (list x y z))  ((t &rest rest) :else))")
    [0 1 2])
  )
