(import [nose.tools [eq_  assert-equal assert-not-equal]])
(defn assert-all-equal [&rest tests]
  (reduce (fn [x y] (assert-equal x y) y)
          tests)
  None)

(eval-and-compile
  (import  [hyclb.core [*]])
  (require [hyclb.core [*]])
  (import   [hyclb.cl4hy [*]])
  (require  [hyclb.cl4hy [*]])
)



(defn test-defmacro-cl []
  
  ;;(eval-and-compile
    (defmacro/cl clmac1 (x y) `(+ ,x ,y))
  ;;)
  (eq_    (cl_eval_hy    (clmac1 111 31 ))    142)

  (eq_
    (cl_eval_hy_qexpr `(MACROEXPAND-DAMMIT:MACROEXPAND-DAMMIT  (clmac1 111 32 )) )
    143    )
  
  (defun tmpfn (u v)
    (clmac1 u v))
  (eq_
    (tmpfn 20 4)
    24    )

  ;;(eval-and-compile
  (defmacro/cl clmac2 (x &optional (y 10) ) `(+ ,x ,y))
  ;;)

  (eq_     (cl_eval_hy    (clmac2 101 ))  111       )


  ;;from https://stackoverflow.com/questions/61967535/self-can-not-use-as-arguments-of-a-hy-macro

  (defmacro setpropv [module  prop v]   `(setv (. ~module ~prop ) ~v))
  
  (defmacro/cl optional_assign (x &optional (base 'self))
    `(lif ,x (setpropv ,base ,x ,x) (setpropv ,base ,x None) ))
  
  (defclass clsa []
    (defun __init__ (self y)
      (optional_assign y)
      ))
  (setv insa1 (clsa 123))
  (eq_  insa1.y 123)

  
  )
