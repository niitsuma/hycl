

(import [nose.tools [eq_  assert-equal assert-not-equal]])


(defn test_defn []
  (defn test_evaled_fn1 [x y] (+ x y)) 
  (eq_
    (test_evaled_fn1 3 5)
    8)
  )

(defn test_eval []
  (eval
    '(defn test_evaled_fn2 [x y] (+ x y))
    )
  (eq_
    (test_evaled_fn2 3 5)
    8)
  ;;NameError: name 'test_evaled_fn2' is not defined
  )


(defn test_read []
  (import [io [StringIO]])
  (setv code  "(defn test_evaled_fn3 [x y] (+ x y))"
        file_like_io  (StringIO code) )
  (eval (read file_like_io))
  (eq_
    (test_evaled_fn3 10 3)
    13)
  ;;NameError: name 'test_evaled_fn3' is not defined
  )

