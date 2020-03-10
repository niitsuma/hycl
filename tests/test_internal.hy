
(import [nose.tools [eq_  assert-equal assert-not-equal]])


(import  [hyclb.core [*]])
(require [hyclb.core [*]])

(import   [hyclb.cl4hy [*]])
(require  [hyclb.cl4hy [*]])

;;(import  [hyclb.models [hyclvector hycllist]] )


(defn test-internal []
    (eq_
    (clisp.readtable.read_str "#(1 2 3)")
    (cl_eval_hy_str "(vector 1 2 3)")
    ;;[1 2 3]
    )

  (eq_
    (clisp.readtable.read_str "(1 . 2)")
    (cons 1 2)
    )
  
  (eq_
    (clisp.readtable.read_str "(1 2 . 3)")
    (cons 1 (cons 2 3))
    )

  )
  
