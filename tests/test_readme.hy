(import [nose.tools [eq_  assert-equal assert-not-equal]])

(require [hy.contrib.walk [let]])

(import  [hyclb.core [*]])
(require [hyclb.core [*]])

(import   [hyclb.cl4hy [*]])
(require  [hyclb.cl4hy [*]])

(defn assert-all-equal [&rest tests]
  (reduce (fn [x y] (assert-equal x y) y)
          tests)
  None)


(defn test_readme []

  (setv clisp (Clisp :quicklisp True))

  (assert-all-equal
    (clisp.eval_str   "(+ 2 5)")
    (clisp.eval_qexpr '(+ 2 5) )
    (cl_eval_str      "(+ 2 5)")
    (cl_eval_qexpr    '(+ 2 5) )
    7)

  
  (eq_
    (list/cl 1 2 3)
    '(1 2 3))
  (eq_
    (vector/cl 1 2 3)
    [1 2 3])
  
  (eq_
    (assoc/cl 'x {'x 10 'y 20})
    (cons 'x 10)
    )
  (eq_
    (assoc/cl 'z {'x 10 'y 20})
    nil/cl
    )
  (eq_
    (assoc/clp 'z {'x 10 'y 20})
    None
    )
  
  (eq_
    (dbind
      (a (b c) d) 
      (1 (2 3) 4)
      [a b c d])
    [1 2 3 4])

  
  )


