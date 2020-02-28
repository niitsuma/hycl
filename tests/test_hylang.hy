

(import [nose.tools [eq_  assert-equal assert-not-equal]])


(defn test_hylang_defn []
  (defn test_evaled_fn1 [x y] (+ x y)) 
  (eq_
    (test_evaled_fn1 3 5)
    8)
  )

(defn test_hylang_eval []
  (eval
    '(do (global test_evaled_fn2)(defn test_evaled_fn2 [x y] (+ x y)))
    )
  (eq_
    (test_evaled_fn2 3 5)
    8)
  ;;NameError: name 'test_evaled_fn2' is not defined
  
  (eval '(defn test_evaled_fn2 [x y] (+ 10 x y)))
  (eq_   (eval '(test_evaled_fn2 3 5))    18)

  )


(defn test_hylang_read []
  (import [io [StringIO]])
  (setv code  "(do (global test_evaled_fn3)(defn test_evaled_fn3 [x y] (+ x y)))"
        file_like_io  (StringIO code) )
  (eval (read file_like_io))
  (eq_
    (test_evaled_fn3 10 3)
    13)
  ;;NameError: name 'test_evaled_fn3' is not defined
  )

