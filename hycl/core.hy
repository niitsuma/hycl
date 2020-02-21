

(import [collections.abc [Iterable]])
(import  functools)

(require [hy.contrib.loop [loop]])
(require [hy.contrib.walk [let]])


;; (import [cons [cons :as  cons/py car :as car/py cdr :as cdr/py]]) ;;;can not apply on lisp
;; (import [cons.core [ConsPair MaybeCons ConsNull]])

(eval-and-compile
  ;;(import [hy.models [HyObject HySequence]])
  ;;(import [hycl.nil [*]])

  (defclass Nil/cl
    []
    ;;[HySequence]
    (defn --init-- [self]
      (setv
        self.car self
        self.cdr self)))

  (setv nil/cl (Nil/cl))
  
  (defn null/cl [x]
    (cond
      [(instance? Nil/cl x) True]
      [(= [] x) True]
      [(= (,) x) True]
      [(= '() x) True]
      [True False]))
  )

;; take ConsPair from ohttps://github.com/algernon/adderall/blob/master/adderall/internal.hy
(defclass ConsPair [Iterable]
  "Construct a cons list.

A Python `list` is returned when the cdr is a `list` or `None`; otherwise, a
`ConsPair` is returned.

The arguments to `ConsPair` can be a car & cdr pair, or a sequence of objects to
be nested in `cons`es, e.g.

    (ConsPair car-1 car-2 car-3 cdr) == (ConsPair car-1 (cons car-2 (cons car-3 cdr)))
"
  (defn --new-- [cls &rest parts]
    (if (> (len parts) 2)
        (reduce (fn [x y] (ConsPair y x))
                (reversed parts))
        ;; Handle basic car, cdr case.
        (do (setv car-part (-none-to-empty-or-list
                             (first parts)))
            (setv cdr-part (-none-to-empty-or-list
                             (if
                               (and (coll? parts)(> (len parts) 1))
                               (last parts)
                               ;;None
                               nil/cl
                               )))
            (cond
              [(instance? Nil/cl cdr-part)
               `(~car-part)]
              [(instance? hy.models.HyExpression cdr-part)
               `(~car-part ~@cdr-part)]
              [(tuple? cdr-part)
               (tuple (+ [car-part] (list cdr-part)))]
              [(list? cdr-part)
               ;; Try to preserve the exact type of list
               ;; (e.g. in case it's actually a HyList).
               (+ ((type cdr-part) [car-part]) cdr-part)]
              [True
               (do
                 (setv instance (.--new-- (super ConsPair cls) cls))
                 (setv instance.car car-part)
                 (setv instance.cdr cdr-part)
                 instance)]))))
  (defn --hash-- [self]
    (hash [self.car, self.cdr]))
  (defn --eq-- [self other]
    (and (= (type self) (type other))
         (= self.car other.car)
         (= self.cdr other.cdr)))
  (defn --iter-- [self]
    (yield self.car)
    (if (coll? self.cdr) ;;(list? self.cdr)
        (for [x self.cdr] (yield x))
        (raise StopIteration))
    )
  (defn --repr-- [self]
    (.format "({} . {})" self.car self.cdr)))

(defn -none-to-empty-or-list [x]
  (cond
    ;;[(none? x) (list)]
    [(tuple? x) x]
    [(and (coll? x)
          (not (cons? x))
          (not (list? x)))
     (list x)]
    [True x]))

;; A synonym for ConsPair
(setv cons ConsPair)

;; (defun car (ls)
;;   (first ls))

(defn car [z]
  (if (null/cl z) nil/cl
      (or (getattr z "car" None)
          (-none-to-empty-or-list (first z)))))

(defn cdr [z]
  (if (null/cl z) nil/cl
      (or (getattr z "cdr" None)
          (cond
            [(instance? range z) (cut z 1)]
            [(iterator? z) (rest z)]
            [True ;;(or (tuple? z) (list? z))
             ((type z) (list (rest z)))]
            ;;[True (rest z)]
            ;;  ;; Try to preserve the exact type of list
            ;;  ;; (e.g. in case it's actually a HyList).
            ;;((type z) (list (rest z)))
        ))))


(defn cons? [a]
  (cond [(null/cl a) False]
        [(instance? ConsPair a) True]
        ;;[(coll? a) (not (empty? a)) True]
        [(or (list? a) (tuple? a) ) (not (empty? a)) True]
        [True False])
  ;; (if (or (and
  ;;           (list? a)
  ;;           (not (empty? a)))
  ;;         (instance? ConsPair a))
  ;;     True
  ;;     False))
  )


(defn consp [el]  (cons? el))
(defn atom/cl [x] (not (cons? x)))

(defmacro! if/clp [o!c x &optional y ]
  `(if (null/cl ~o!c) ~y (if ~o!c ~x ~y)))

(defmacro! if/cl [o!c x &optional [y [] ] ]
  `(if (null/cl ~o!c) ~y (if ~o!c ~x ~y)))
;; (defn if/cl [test x &optional [y nil/cl]]
;;   (if (null/cl test) y (if test x y)))
;;(if/cl [] True )

;; renamed functions
;;   (defmacro! setf (&rest args)
;;     ;; Beware of humongous stdout(in repl)!!
;;     `(do
;;        (setv ~@(get args (slice 0 (- (len args) 2))))       
;;        (setv ~@(get args (slice -2 None)))
;;        ~(get args -2)))
;; (+ 1 1)
(defmacro typep [obj objtype]
  `(is (type ~obj) ~objtype))

;;   ;; todo: &optional cannnot accept () form. (now only stupid [])
;;   (defmacro defun (name lambda-list doc &rest body)
;;     (setv lambda-list (lfor el lambda-list 
;;                             (if (is (type el) HyExpression)
;;                                 (list el)
;;                                 el))) 
;;     (if (not (typep doc str))
;;         `(defn ~name ~(list lambda-list) ~@(cons doc (HyExpression body)))
;;         `(defn ~name ~(list lambda-list) doc ~@body)))
(defn eq [x y]      (is x y))
(defn equals [x y]  (= x y))

;; ;; numerical functions
(defn mod [n m] (% n m))
(defn zerop [n] (= n 0))
(defn plusp [n] (> n 0))
(defn minusp [n] (< n 0))
(defn oddp [n] (zerop (mod n 2)))
(defn evenp [n] (not (oddp n)))
(defn divisible [n m] (zerop (mod n m)))

(defmacro incf [n  &optional [delta 1]]
  `(setv ~n (+ ~n ~delta)))

(defmacro decf [n &optional [delta 1]]
  `(setv ~n (- ~n ~delta)))

(defmacro 1+ [n]
  `(+ ~n 1))

(defmacro 1- [n]
  `(- ~n 1))

;; ;; list functions

;; (defun lst (&rest args)
;;   (HyExpression args))

(defn length [l] (len l))
(defn emptyp [l] (empty? l))

(defn caar [ls]  (-> ls car car))
(defn cddr [ls]  (-> ls cdr cdr))
(defn cadr [ls]  (-> ls cdr car))
(defn cdar [ls]  (-> ls car cdr))

(defn apply/cl [f ls]  (f #*ls))

;; (defmacro push (el ls)
;;   `(setf ~ls (cons ~el ~ls)))

(defn nreverse [ls]
  (cond
    [(list? x)
     (do (.reverse ls)
         ls)]
    [True (do
            (setv tmp (list ls))
            (.reverse tmp)
            (type ls )tmp)
     ]))

(defn nconc [x y]
  (cond
    [(null/cl x) (cons x y)]
    [(list? x) (do (.extend x y) x)]
    [True (cons x y)] ;;not correct dealing cdr pointer 
    ))

(defn append/cl [x y]
  (if (empty? x) y
      (nconc (car x) (append/cl (cdr x) y))
      ))

(defn mapcan [func ls]
  (if (empty? ls)
      ls
      (append/cl
        (func (car ls))
        (mapcan func (cdr ls)))))

(defmacro progn [&rest body]
  `(do ~@body))


(defn mapcar [func &rest seqs]  ((type (car seqs))  (apply/cl (functools.partial map func) seqs))   )

;;   (defun group (src n)
;;     (HyExpression (apply zip (* [(iter src)] n)))))


(defmacro lambda [lambda-list &rest body]
  `(fn ~(list lambda-list) ~@body))

(defmacro let/cl [var-pairs &rest body]
  (setv var-names (list (map first  var-pairs))
        var-vals  (list (map second var-pairs)))
  `(let [ ~@(+ #*(lfor (, x y) (zip var-names var-vals) [x y]))]
     ~@body
     ))
(defmacro let* [varval &rest body]
  (if (<= (len varval) 1)
      `(let/cl ~varval ~@body)
      `(let/cl (~(first varval))
         (let* ~(cut varval 1)
           ~@body))))

;;   (defmacro! prog1 (&rest body)
;;     `(let ((~g!sexp-1 ~(car body)))
;;           (progn
;;             ~@(cdr body)
;;             ~g!sexp-1)))

;;   (defmacro when (condition &rest body)
;;     `(if ~condition
;;          (progn
;;            ~@body)))

;;   (defmacro unless (condition &rest body)
;;     `(if (not ~condition)
;;          (progn
;;            ~@body)))  

;;   (defun pushr (ls el)
;;     (.append ls el))

;;   (defun pushl (ls el)
;;     (.insert ls 0 el))

;;   )

;; (eval-and-compile
;;   (defun flatten-1 (ls)
;;     (let ((acc ()))
;;          (for [el ls]
;;            (if (consp el)
;;                (nconc acc el)
;;                (.append acc el)))
;;          acc))


(defmacro cond/cl [&rest branches]
  (loop
    ((ls branches)
      (cont (lambda (x) x)))
    (if ls
        (recur (cdr ls) (lambda (x) (cont `(if/cl ~(caar ls)
                                                  (progn ~@(cdar ls)) 
                                                  ~x))))
        (cont [] ))))


;;   (defmacro! case (exp &rest branches)
;;     `(let ((~g!val ~exp))
;;           (cond/cl ~@(list (map (lambda (br)
;;                                   (if (= (car br) 'otherwise)
;;                                       `(True ~@(cdr br))
;;                                       `((eq ~g!val ~(car br)) ~@(cdr br))))
;;                                 branches)))))

(defn subseq [seq start &optional end] (cut seq start end))


(defn destruc [pat seq n]
  (let [nil ((type pat) (list))]
    (if (null/cl pat)
        nil
        (let [res (cond
                    [(atom/cl pat) pat]
                                ;[(eq (car pat) '&rest) (cadr pat)]
                    [True nil])]
          (if/cl res
                 `((~res (subseq ~seq 0 ~n)))
                 (let
                   [p (car pat)
                    rec (destruc (cdr pat) seq (inc n))]
                   (if (atom/cl p)
                       (cons
                         `(~p (get ~seq ~n))
                         rec)
                       (let [var (gensym)]
                         (cons (cons `(~var (get ~seq ~n))
                                     (destruc p var 0))
                               rec)))))))))

(defn dbind-ex [binds body]
  (if (null/cl binds)
      `(do ~@body)
      `(let/cl
         ~(mapcar (fn [b]
                    (if (cons? (car b))
                        (car b)
                        b))
                  binds)
         ~(dbind-ex (mapcan (fn [b]
                              (if (cons? (car b))
                                  `(~(cdr b))
                                  '()))
                            binds)
                    body))))


(defmacro! dbind [pat seq &rest body]
  (if (instance? hy.models.HyExpression seq)
      (+ '(let) `([~g!seq (quote ~seq)])
         `( ~(dbind-ex (destruc pat g!seq 0) body))  )
      (+ '(let) `([~g!seq ~seq])
         `( ~(dbind-ex (destruc pat g!seq 0) body))
         )))


(defn values [&rest returns]   (tuple returns))

;;   ;; multiple-value-bind
;;   (defmacro mvb (var-list expr &rest body)
;;     `(dbind ~var-list ~expr ~@body))

(defmacro multiple-value-bind [var-list expr &rest body]
  (setv n1 (len var-list)
        n2 (len expr) )
  `(do (setv
         ~@(mapcan
             (fn [k]
               (if (< k n2)
                   [(get var-list k) (get expr k)]
                   [(get var-list k) None ] ))
             (list (range n1))))
       ~@body
       ))

(defmacro multiple-value-bind/cl [var-list expr &rest body]
  (setv n1 (len var-list)
        n2 (len expr) )
  `(do (setv
         ~@(mapcan
             (fn [k]
               (if (< k n2)
                   [(get var-list k) (get expr k)]
                   [(get var-list k) []  ] ))
             (list (range n1))))
       ~@body
       ))


;;   ;; errors
;;   (defmacro! ignore-errors (&rest body)
;;     `(try
;;        ~@body
;;        (except [~g!err Exception]
;;          nil)))

;;   (defmacro! unwind-protect (protected &rest body)
;;     `(try
;;        ~protected
;;        (except [~g!err Exception]
;;          ~@body
;;          (raise ~g!err))))

;;   ;; sharp macros
;;   (defmacro! pr (o!arg)
;;     `(do
;;        (print ~o!arg)
;;        ~o!arg))


(defn assoc/clp [e dic] (if (in e dic) (get dic e) None))
(defn assoc/cl  [e dic] (if (in e dic) (get dic e) [])) ;;nil/cl))
;; (assoc/cl 'x {'x 10 'y 20})

