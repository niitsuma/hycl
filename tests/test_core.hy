(import [nose.tools [eq_  assert-equal assert-not-equal]])

(require [hy.contrib.walk [let]])

;;(import  [hycl.cons [*]])
(import  [hycl.nil [*]])
(import  [hycl.core [*]])
(require [hycl.core [*]])


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
    nil/cl
    )
  (assert-all-equal
    (if/pcl nil/cl True )    
    (if/pcl [] True )
    (if/pcl (,) True )
    (if/pcl '() True )
    None
    )
)

(defn test-null []
  (assert-all-equal
     (null/cl? nil/cl)
     (null/cl? [])
     (null/cl? (,))
     (null/cl? '())
     True)
  ;; (eq_
  ;;   (nil/cl-macro )
  ;;   nil/cl)
  )

(defn test-assoc []
  (eq_
    (assoc/cl 'x {'x 10 'y 20})
    10
    )
  (eq_
    (assoc/cl 'z {'x 10 'y 20})
    nil/cl
    )
  (eq_
    (assoc/pcl 'z {'x 10 'y 20})
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
  )
  
(defn test-mapcar []
  (eq_
    (mapcar     (fn [x] [(+ x 10) "x"]) [1 2 3 4])
    [[11 "x"] [12 "x"] [13 "x"] [14 "x"]])

  (eq_
    (mapcar     (fn [x] [(+ x 10) None]) [1 2 3 4])
    [[11 None] [12 None] [13 None] [14 None ]])
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
  ;; (eq_
  ;;   (cond/cl
  ;;     ((= 1 2) "aa")
  ;;     ((= 2 3) "bb"))
  ;;   nil/cl)
  )

(defn test-multiple-value-bind []
  (eq_
    (multiple-value-bind
      (x y z u)
      (1 2 3)
      [x y z u])
    [1 2 3 None] )
  ;; (eq_
  ;;   (multiple-value-bind/cl
  ;;     (x y z u)
  ;;     (1 2 3)
  ;;     [x y z u])
  ;;   [1 2 3 nil/cl]  )
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
