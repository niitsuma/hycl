(import [nose.tools [eq_  assert-equal assert-not-equal]])

(require [hy.contrib.walk [let]])

;;(import  [hycl.cons [*]])
;;(import  [hycl.nil [*]])
(import  [hycl.core [*]])
(require [hycl.core [*]])

(import  [hycl.util [*]])
(require [hycl.util [*]])


(defn assert-all-equal [&rest tests]
  (reduce (fn [x y] (assert-equal x y) y)
          tests)
  None)

(defn test-cons []
  (eq_
    (cons 'a [])
    ['a])
  (eq_
    (cons 'a (,))
    (,'a))
  (eq_ 
    (cons 'a '())
    '(a))
  (eq_
    (cons 'a ['b 'c])
    ['a 'b 'c])
  (eq_
    (cons 'a (, 'b 'c))
    (,'a 'b 'c))
  (eq_
    (cons 'a '(b c))
    '(a b c))
  (assert-not-equal
    (cons 'a (, 'b 'c))
    (, 'a))
  (eq_
    (cons '(a b) '(c d))
    '((a b) c d))
  (eq_
    (cons 'a (, 'b 'c))
    (, 'a 'b 'c)  )
  (eq_
    (cons '(a b) '(c))
    '((a b) c)  )
  (eq_
    (cons ['a 'b] ['c])
    [['a 'b] 'c]  )
  (eq_
    (cons (, 'a 'b) (, 'c))
    (, (, 'a 'b) 'c)  )
  (eq_
    (car (cons 'a 'b))
    'a)
  (eq_
    (car (cons '(a b) 'a))
    '(a b))
  (eq_
    (car (cons ['a 'b] 'a))
    ['a 'b])
  (eq_
    (car (cons (, 'a 'b) 'a))
    (, 'a 'b) )
  (eq_
    (car (cons (, 'a 'b) 'a))
    (, 'a 'b))
  (eq_
    (cdr (cons 'a 'b))
    'b)
  (eq_
    (cdr (cons 'a '()))
    '())
  (eq_
    (cdr (cons 'a (,)))
    (,))
  (eq_
    (cdr (cons 'a []))
    [])
  (eq_
    (cdr (cons 'a '(b)))
    (cdr (cons '(a) '(b)))
    '(b))
  (assert-all-equal
    (cdr (cons 'a ['b]))
    ['b])
  (eq_
    (cdr (cons 'a (, 'b)))
    (, 'b))
  (eq_
    (cdr (cons 'a (, 'b)))
    (, 'b))
  )


(defn test-if []
  (assert-all-equal
    (if/cl nil/cl True )    
    (if/cl [] True )
    (if/cl (,) True )
    (if/cl '() True )
    ;;nil/cl
    []
    )
  (assert-all-equal
    (if/clp nil/cl True )    
    (if/clp [] True )
    (if/clp (,) True )
    (if/clp '() True )
    None
    )
)

(defn test-null []
  (assert-all-equal
     (null/cl nil/cl)
     (null/cl [])
     (null/cl (,))
     (null/cl '())
     True)
  )

(defn test-assoc []
  (eq_
    (assoc/cl 'x {'x 10 'y 20})
    10
    )
  (eq_
    (assoc/cl 'z {'x 10 'y 20})
    ;;nil/cl
    []
    )
  (eq_
    (assoc/clp 'z {'x 10 'y 20})
    None
    )
  )


(defn test-mapcan []
  (eq_
    (mapcan     (fn [x] [(+ x 10) "x"]) [1 2 3 4])
    [11 "x" 12 "x" 13 "x" 14 "x"])
  (eq_
    (mapcan     (fn [x] [(+ x 10) None]) [1 2 3 4])
    [11 None 12 None 13 None 14 None])
  (eq_
    (mapcan     (fn [x] [(+ x 10) []]) [1 2 3 4])
    [11 [] 12 [] 13 [] 14 [] ])
  (eq_
    (append/cl [1 []] [3 4 []] )
    [1  [] 3 4  [] ]
    )

  )
  
(defn test-mapcar []
  (eq_
    (mapcar     (fn [x] [(+ x 10) "x"]) [1 2 3 4])
    [[11 "x"] [12 "x"] [13 "x"] [14 "x"]])

  (eq_
    (mapcar     (fn [x] [(+ x 10) None]) [1 2 3 4])
    [[11 None] [12 None] [13 None] [14 None ]])
  (eq_
    (mapcar     (fn [x] [(+ x 10) [] ]) [1 2 3 4])
    [[11 []] [12 []] [13 []] [14 [] ]])
  )

(defn test-let/cl []
  (eq_
    (let/cl ((x 1)
             (y 2))
      (setv y (+ x y))
      [x y])
    [1 3] )
  )


(defn test-cond/cl []
  (eq_
    (cond/cl
      ((= 1 2) "aa")
      ((= 2 2) "bb"))
    "bb")
  (eq_
    (null/cl
      (cond/cl
        ((= 1 2) "aa")
        ((= 2 3) "bb")))
    True)
  (eq_
    (cond/cl
      ((= 1 2) "aa")
      ((= 2 3) "bb"))
    []
    )
  )

(defn test-multiple-value-bind []
  (eq_
    (multiple-value-bind
      (x y z u)
      (1 2 3)
      [x y z u])
    [1 2 3 None] )

  (eq_
    (multiple-value-bind/cl
      (x y z u)
      (1 2 3)
      [x y z u])
    [1 2 3 [] ] )
  
  
  ;; (eq_
  ;;   (null/cl
  ;;     (get
  ;;       (multiple-value-bind/cl
  ;;         (x y z u)
  ;;         (1 2 3)
  ;;         [x y z u])
  ;;       3))
  ;;   True)
  
  )

(defn test-dbind []
  (eq_
    (dbind
      (a (b c) d) (1 (2 3) 4)
      [a b c d])
    [1 2 3 4]
    )

  (eq_
    (dbind
      (a (b c) d) (1 [2 3] 4)
      [a b c d])
    [1 2 3 4]
    )
  
   (eq_
    (dbind
      (a (b c) d) [1 [2 3] 4]
      [a b c d])
    [1 2 3 4]
    )
  )

(defn test-defun []
  
  (defun testfn (x y)
    (if x y (+ 3 y)))
  
  (eq_
    (testfn 1 2)
    2)
  (eq_
    (testfn nil/cl 2)
    5)

  (defun testfn2 (x y)
    (setq z 20)
    (if x (+ z y)))

  (eq_
    (testfn2 1 2)
    22)

  (eq_
    (testfn2 [] 2)
    [])
  
  
  )
    