
(import re)
(import copy)
(import hy)
(require [hy.contrib.loop [loop]])
(require [hy.contrib.walk [let]])
(import [hy.contrib.walk [postwalk prewalk walk]])

;; (import  [hyclb.core [*]])
;; (require [hyclb.core [*]])

(import [hy.contrib.hy-repr [hy-repr hy-repr-register -cat]])

(import cl4py)

;; (import [cons [cons :as  cons/py car :as car/py cdr :as cdr/py]]) ;;;can not apply on lisp
;; (import [cons.core [ConsPair MaybeCons ConsNull]])
(import [gasync.core [q-exp-fn?]])
(defn q-exp-fn0?        [p f] (and (coll? p) (= (first p) f)))

(import  [hyclb.models [hyclvector hycllist]] )

;; (hy-repr-register
;;   hyclvector
;;   :placeholder "#(...)"
;;   (fn [x]
;;     (setv text (.join " " (gfor  v  x (hy-repr v))))
;;     ;; (global -quoting)
;;     ;; (setv -quoting True)
;;     ;;(setv -quoting-bak -quoting)
;;     (+ "#(" text ")"))
;;     )

(for
  [[types fmt]
   (partition
     [
      ;;[list HyList] "[...]"
      [list HyList hyclvector] "#(...)"
      ;;[set HySet] "#{...}"
      ;;frozenset "(frozenset #{...})"
      ;;dict-keys "(dict-keys [...])"
      ;;dict-values "(dict-values [...])"
      ;;dict-items "(dict-items [...])"
      ])]
  (defn mkrepr [fmt]
    (fn [x] (.replace fmt "..." (-cat x) 1)))
  (hy-repr-register types :placeholder fmt (mkrepr fmt)))


(eval-and-compile 
  (import [collections.abc [Iterable]])
  (import  functools)
  (import numpy)

  ;;(defclass HyVector [hy.models.HySequence]  )
  ;;(import [hy.models [HyObject HySequence]])
  
  (defclass SharpsignSharpsign []
    (defn __init__ [self label]
      (setv self.label  label))
    (defn  __repr__ [self]
      (.format "#{}#" self.label)))
  (defclass SharpsignEquals [];;hy.models.HyObject]
    (defn __init__ [self label obj]
      (setv self.label  label
            self.obj  obj))
    (defn __repr__ [self]
      (.format "#{}={}" self.label (hy-repr self.obj))))  
  

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
                [(instance? Nil/cl cdr-part) `(~car-part)]
                [(instance? hy.models.HyExpression cdr-part) `(~car-part ~@cdr-part)]
                [(tuple? cdr-part)
                 ((type cdr-part) (tuple (+ [car-part] (list cdr-part))))]
                [(list? cdr-part)
                 ;; Try to preserve the exact type of list
                 ;; (e.g. in case it's actually a HyList).
                 ((type cdr-part) (+ ((type cdr-part) [car-part]) cdr-part))]
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
      ;;(.format "({} . {})" (hy-repr self.car) (hy-repr self.cdr))
      (.format "(cons {} {})" (hy-repr self.car) (hy-repr self.cdr))
      )
    )

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
  (defn list/cl    [&rest args] `(~@args))
  ;;(defn vector/cl  [&rest args] (hyclvector (list args)))
  (defn vector/cl  [&rest args] (list args))

  (setv nan numpy.nan
        NAN numpy.nan)

  (defn consp [el]  (cons? el))
  (defn atom/cl [x] (not (cons? x)))

  (defn eq     [x y]  (is x y))
  (defn eql    [x y]
    (if
      (or
        (instance? int x)
        (instance? int y)
        (instance? float x)
        (instance? float y)
        )
        (= x y) 
        (is x y)
    ))
  (defn equal  [x y]  (= x y))  
  ;;(defn equals [x y]  (= x y))
  (defn equalp [x y]  (= x y))

  ;; ;; numerical functions
  (defn mod [n m] (% n m))
  (defn zerop [n] (= n 0))
  (defn plusp [n] (> n 0))
  (defn minusp [n] (< n 0))
  (defn oddp [n] (zerop (mod n 2)))
  (defn evenp [n] (not (oddp n)))
  (defn divisible [n m] (zerop (mod n m)))

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
      [(list? ls)
       (do (.reverse ls)
           ls)]
      [True (do
              (setv ls-type (type ls))
              (setv tmp (list ls))
              (.reverse tmp)
              (ls-type tmp))
       ]))

  (defn nconc [x y]
    (cond
      [(null/cl x) y]
      [(list? x) (do (.extend x y) x)]
      [True (+ x y)]
      ;;[True (cons x y)] ;;not correct dealing cdr pointer 
      ))

  (defn append/cl [x y]
    (if (coll? y)
        (if (empty? x) y
            ;;(nconc (car x)   (append/cl (cdr x) y))
            (nconc (cut x 0 1) (append/cl (cdr x) y)))
        (cons x y)))

  (defn remove/cl [e l &optional test]
    (cond
      [(and (none? test) (list? l))
       (do 
         (while (in e l)  (.remove l e) )
         l)]
      [(coll? l)
       (do
         (lif-not test (setv test (fn [x] (= x e))))
         ((type l) (filter (fn [x] (not (test x)))  l)))
       ]
      [True l]))
  
  (defn mapcan [func ls]
    (if (empty? ls)
        ls
        (append/cl
          (func (car ls))
          (mapcan func (cdr ls)))))

  (defn mapcar [func &rest seqs]  ((type (car seqs))  (apply/cl (functools.partial map func) seqs))   )

  ;;   (defun group (src n)
  ;;     (HyExpression (apply zip (* [(iter src)] n)))))

  (defn values [&rest returns]   (tuple returns))

  (defn assoc/clp [e dic] (if (in e dic) (cons e (get dic e)) None))
  (defn assoc/cl  [e dic] (if (in e dic) (cons e (get dic e)) nil/cl )  )
  ;; (assoc/cl 'x {'x 10 'y 20})

  (defn svref [v i] (get v i))


  (defn declare/cl   [&rest args]  )
  (defn ignorable/cl [&rest args]  )
  
  (defn dummy-fn/cl [&rest args]  )

  
  (defn sb-c::check-ds-list [&rest args] (first args))

  (defn error/cl [&optional msg] 
    (lif msg (raise (ValueError msg)) (raise ValueError)))

  )

(defmacro! if/clp [o!c x &optional y ]
  `(if (null/cl ~o!c) ~y (if ~o!c ~x ~y)))
(defmacro! if/cl [o!c x &optional [y (,) ] ]
  `(if (null/cl ~o!c) ~y (if ~o!c ~x ~y) ))
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
(defmacro typep/cl [obj objtype]
  `(is (type ~obj) ~(eval objtype)))

(defmacro slot-value/cl [obj slot]
  `(getattr ~obj (str ~slot)))

;;   ;; todo: &optional cannnot accept () form. (now only stupid [])
;;   (defmacro defun (name lambda-list doc &rest body)
;;     (setv lambda-list (lfor el lambda-list 
;;                             (if (is (type el) HyExpression)
;;                                 (list el)
;;                                 el))) 
;;     (if (not (typep doc str))
;;         `(defn ~name ~(list lambda-list) ~@(cons doc (HyExpression body)))
;;         `(defn ~name ~(list lambda-list) doc ~@body)))

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

(defmacro progn [&rest body] 
  `(do ~@body))

(defmacro lambda [lambda-list &rest body]
  `(fn ~(list lambda-list) ~@body))

;; (defmacro let/cl [var-pairs &rest body]
;;   (setv var-names (list (map first  var-pairs))
;;         var-vals  (list (map second var-pairs)))
;;   `((fn [~@var-names] ~@body) ~@var-vals))

(defmacro let/cl [var-pairs &rest body]
  (setv var-names (list (map first  var-pairs))
        var-vals  (list (map second var-pairs)))
  ;;`(let [ ~@(+ #*(lfor (, x y) (zip var-names var-vals) [x y]))]
  ;;`(let [ ~@(mapcan (fn [xy] xy)  (list (zip var-names var-vals))) ]
  ;;`(let [~@(+ #*(lfor (, x y) (zip var-names var-vals) [x y]))]
  `(let [~@(mapcan (fn [xy] `(~@(list xy))) (list (zip var-names var-vals))) ]
     ~@body
     ))

;; (setv var-names (list '(a b c))
;;       var-vals  (list '(1 2 3)))


;; (list (zip var-names var-vals))
;; ;;(+ #*(lfor (, x y) (zip var-names var-vals) [x y]))
;; (mapcan (fn [xy] `(~@(list xy))) (list (zip var-names var-vals)))


;; (let/cl ((x 1)
;;           (y 2))
;;       (setv y (+ x y))
;;       [x y])

;; (defn symbol-macrolet [var-pairs &rest body]
;;   (setv var-names (list (map first  var-pairs))
;;         var-vals  (list (map second var-pairs)))
;;   (+
;;     `(do)
;;     (lfor (, x y) (zip var-names var-vals)
;;           `(defn ~x [] ~y)
;;           )
;;     #*body
;;     ))

;; (hy-repr
;; (symbol-macrolet
;;   '(( x ( print  1))
;;     ( y ( print  2)))
;;   '(print 10)
;;   '(print 20)
;;   ;;'x
;;   )
;; )




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
                    ;;[(eq (car pat) '&rest) (cadr pat)]
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



;;(defmacro return-from [exi val] `(return ~val))
;; (defmacro block [exi &rest body]
;;   `(do
;;      (defn ~exi [] ~@body)
;;      (~exi)     )  )

(defmacro block [return_name &rest body]
  ;;(setv return-name (gensym 'blockname))
  (setv e (gensym 'e))
  `(do
     (defclass ~return_name [Exception]
       (defn __init__ [self ret]:
         (setv self.return_value ret)))
     (try
       ~@body
       (except [~e ~return_name]
         (. ~e return_value) ))))
(defmacro return-from [return_name return_value]
  `(raise (~return_name ~return_value)))


(defn qexp-pickup-variables [code]
  (setv varis [])
  (defn picker [p]
    (if (q-exp-fn? p 'setv)
        (for [(, i e)  (enumerate (cut p 1 None))]
          (if (= (% i 2) 0)
              (varis.append e))))
    p )
  (prewalk picker code)
  (list (set varis))
  )

;; (qexp-pickup-variables '(do
;;                           (print 3)
;;                           (setv x 2
;;                                 y 3)
;;                           (print u)
;;                           )
;;                        )


(defn progn-like-qexp-body-mod [p modfn]
  (cond
    [(or
       (q-exp-fn? p 'do)
       (q-exp-fn? p 'progn)
       (q-exp-fn? p 'block)
       (q-exp-fn? p 'tagbody)
       )
     (+ (cut p None 1)
        (modfn (cut p 1 None)))]
    [(or
       (q-exp-fn? p 'let)
       (q-exp-fn? p 'let*)
       (q-exp-fn? p 'let/cl)
       (q-exp-fn? p 'symbol-macrolet)
       )
     (+ (cut p None 2)
        (modfn (cut p 2 None))) ]
    [True 
     (do 
       (setv p2 (modfn `(~p) ))
       (if (> (len p2) 1)
           `(do ~@p2)
           (first p2)))]
    )
  )


(defn tagbody-qexp-body-change [ps fname labels label_dic varis]
  (setv startfname (copy.copy fname))
  (setv scope_labels  [])
  (lif fname (+= scope_labels  [(copy.copy fname)]))
  (+=  scope_labels
       (list
         (filter
           (fn [p] (and (symbol? p)(in p labels)))  ps)))

  ;;(print "scope_labels" (hy-repr scope_labels))

  (defn has_go_scope_labels? [p]
    (setv lbls [])
    (defn phas? [p]
      (if (and (q-exp-fn? p 'go) (in (get p 1) scope_labels))
          (lbls.append (get p 1) ))
      p)
    (prewalk phas? p)
    (list (set lbls))
    )
  
  (setv ret1 [])
  (setv codedic (dfor k scope_labels [k []] ))
  (setv buf [])
  (for [p ps]
    (if (and (symbol? p)(in p labels))
        (do
          (setv fnext p)
          (lif fname
               (setv (get codedic fname) buf)
               (ret1.extend buf)
               )
          (setv buf [])
          (setv fname p))
        (buf.append p)
        ;; (buf.append
        ;;   (progn-like-qexp-body-mod
        ;;     p
        ;;     (fn [ps] (tagbody-qexp-body-change ps None labels label_dic))
        ;;     ))
        ))
  (lif fname 
       (setv (get codedic fname) buf)
       (ret1.extend buf)
       )
  
  (setv refered (dfor k scope_labels [k False] ))
  (defn next_label [k]
    (lif-not
      k
      (first scope_labels)
      (do
        (setv i (.index scope_labels k))
        (+= i 1)
        (if (>= i (len scope_labels))
            None
            (get  scope_labels i)))))
  (defn retcode [code lnext]
    ;;(print "retcode lnext" lnext (hy-repr code))
    (setv buf [])
    (for [p code]
      (setv lbls (has_go_scope_labels? p))
      (for [lbl lbls]
        (if (not (get refered lbl))
            (do
              (setv (get refered lbl) True)
              (buf.append
                (+
                  `(defn ~(get label_dic lbl) [~@varis])
                  (retcode (get codedic lbl) (next_label lbl)))))))
      (if (q-exp-fn? p 'go)
          (buf.append `(return (~(get label_dic (get p 1)) ~@varis)   ))
          (buf.append p)
          
          ;; (buf.append
          ;;   (progn-like-qexp-body-mod
          ;;     p
          ;;     (fn [ps] (tagbody-qexp-body-change ps None labels label_dic))
          ;;     ))
          ))
    (lif
      lnext
      (do
        (if (not (get refered lnext))
            (do
              (setv (get refered lnext) True)
              (buf.append
                (+ 
                  `(defn ~(get label_dic lnext) [~@varis])
                  (retcode (get codedic lnext) (next_label lnext))))))
        (buf.append `(~(get label_dic lnext) ~@varis ) )))
    buf)
  
  (retcode ret1 (next_label None))
  )

(defn tagbody-qexp [qexp]
  (setv varis (qexp-pickup-variables qexp))
  (setv labels [])
  (defn picker [p] (if (q-exp-fn? p 'go)  (labels.append (get p 1)) )   p )
  (prewalk picker qexp)
  ;;(print labels)
  (setv startfname (gensym 'tagbody))
  (setv label_dic (dfor l labels [l (gensym l)]))
  (setv (get label_dic startfname) startfname)
  ;;(print label_dic) 
  ;;(tagbody-qexp-body-change (cut qexp 1 None) startfname labels label_dic)
  (prewalk 
    (fn [ps]
      (progn-like-qexp-body-mod
        ps
        (fn [ps] (tagbody-qexp-body-change ps None labels label_dic varis))
        ))
    `(do ~@qexp))
  )

(defmacro tagbody [&rest body]
  (setv startfname (gensym 'tagbody))
  `(do
     (defn ~startfname []
       ~@(cut (tagbody-qexp body)  1 None))
     (~startfname)))



(defn qexp-var-pairs-hy2cl [var-pairs]
  (if (symbol? (first var-pairs))
      (do
        (setv ret '()
              buf '()
              )
        (for [(, k p) (enumerate var-pairs)]
          ;;(print k p (hy-repr (cut var-pairs k (+ 2 k) )))
          (if (even? k)
              (+= ret `(~(cut var-pairs k (+ 2 k) )))))
        ret)
      var-pairs))

(defn qexp-cl-var-pairs-colon-mod [var-pairs]
  (setv var-vals  (list (map second var-pairs))
        var-names (list (map first  var-pairs))
        var-pairs2 '())
  (for [(, k v) (enumerate var-names)]
    (setv token (str v)
          m (re.fullmatch cl4py.reader.symbol_regex token)
          package  (m.group 1)
          delimiter (m.group 2)
          name  (m.group 3))
    ;;(print "symbol=" token package delimiter name )
    (if (= delimiter ":")
        (do 
          (setv v_new (hy.models.HySymbol  (+ package "::" name)))
          (if (not (in v_new var-vals))
              (+= var-pairs2 `((~v_new ~(get var-vals k))))))
        (if (= delimiter "::")
            (do 
              (setv v_new (hy.models.HySymbol (+ package ":" name)))
              (if (not (in v_new var-vals))
                  (+= var-pairs2 `((~v_new ~(get var-vals k))))))))
    )
  ;;(print (hy-repr var-pairs2))
  (+ var-pairs var-pairs2))

;; (hy-repr
;; (qexp-cl-var-pairs-colon-mod
;;   '((foo (+ 2 3)))
;;   ))

(defn qexp-var-pairs-add [vpar vpar-add]
  ;;(setv vpar-add (get p 1))
  (if (not (empty? vpar-add))
      (do 
        (setv
          ;;vpar-add (qexp-cl-var-pairs-colon-mod vpar-add)
          vnam-add (list (map first  vpar-add))
          vpar-mod `(~@(list (filter (fn [x] (in (first x) vnam-add)) vpar)))
          vnam-mod (list (map first  vpar-mod))
          vpar-mod `(~@(list (filter (fn [x] (in (first x) vnam-mod)) vpar-add)))
          vpar-res `(~@(list (filter (fn [x] (not (in (first x) vnam-mod))) vpar)))
          vpar-add `(~@(list (filter (fn [x] (not (in (first x) vnam-mod))) vpar-add)))
          vpar (+ vpar-res vpar-mod vpar-add )
          )
        vpar)
      vpar))
  
(defn qexp-var-pairs-sub [vpar vpar-ignore]
  (if (not (empty? vpar-ignore))
      (do 
        (setv vnam-ignore (list (map first vpar-ignore))
              vpar `(~@(list (filter (fn [x] (not (in (first x) vnam-ignore))) vpar))))
        vpar)
      vpar))
      
(defn qexp-symbol-macrolet-apply-deep [p vpar &optional cl-mode]
  (if (or
        (q-exp-fn? p 'let)
        (q-exp-fn? p 'let*)
        (q-exp-fn? p 'let/cl)
        )
      (do
        (setv vpar-ignore (get p 1))
        (if (q-exp-fn? p 'let)  (setv vpar-ignore (qexp-var-pairs-hy2cl vpar-ignore)))
        (lif cl-mode (setv vpar-ignore  (qexp-cl-var-pairs-colon-mod vpar-ignore)))
        (setv vpar (qexp-var-pairs-sub vpar vpar-ignore))
        )
      (if (q-exp-fn? p 'symbol-macrolet)
          (do
            (setv vpar-add (get p 1))
            (lif cl-mode (setv vpar-add  (qexp-cl-var-pairs-colon-mod vpar-add)))
            (setv vpar (qexp-var-pairs-sub vpar vpar-add)))))
  (setv vnam  (list (map first  vpar))
        vval  (list (map second vpar)))
  (for [v vnam] (if (= `(~v) p) (return p)))
  (if
    (and (symbol? p) (in p vnam) ) (get vval (.index vnam p))
    (if
      (not (coll? p)) 
      p
      (do
        (if (q-exp-fn? p 'symbol-macrolet)
            (do 
              (setv pa (cut p 0 2)
                    pb (cut p 2 None))
              (+
                pa
                (walk
                  (fn [p0] (qexp-symbol-macrolet-apply-deep p0 vpar))
                  identity pb)))
            (do
              (walk
                (fn [p0] (qexp-symbol-macrolet-apply-deep p0 vpar))
                identity p)))))))
                      
      


(defn symbol-macrolet-cl-qexp-inner [p vpar
                                     &optional
                                     else-task
                                     cont-walk-base
                                     ]
  ;; (print "symbol-macrolet-cl-qexp-inner")
  ;; (print "vpars" (hy-repr vpar))
  ;; (print  (hy-repr p))
  (if (or
        (q-exp-fn? p 'let)
        (q-exp-fn? p 'let*)
        (q-exp-fn? p 'let/cl)
        )
      (do
        (setv vpar-ignore
              (cond 
                [(q-exp-fn? p 'let) (qexp-cl-var-pairs-colon-mod (get p 1))]
                [(or (q-exp-fn? p 'let*) (q-exp-fn? p 'let/cl))  (get p 1)]
                [True '()]
                ))
        (if (not (empty? vpar-ignore))
            (do 
              (setv vpar-ignore (qexp-cl-var-pairs-colon-mod vpar-ignore)
                    vnam-ignore (list (map first vpar-ignore))
                    vpar `(~@(list (filter (fn [x] (not (in (first x) vnam-ignore))) vpar)))))))
      (if (q-exp-fn? p 'symbol-macrolet)
          (do
            ;;(print "symbol-macrolet-cl-qexp-inner smlet" vpar)
            (setv vpar-add (get p 1))
            (if (not (empty? vpar-add))
                (do 
                  (setv vpar-add (qexp-cl-var-pairs-colon-mod vpar-add)
                        vnam-add (list (map first  vpar-add))
                        vpar-mod `(~@(list (filter (fn [x] (in (first x) vnam-add)) vpar)))
                        vnam-mod (list (map first  vpar-mod))
                        vpar-mod `(~@(list (filter (fn [x] (in (first x) vnam-mod)) vpar-add)))
                        vpar-res `(~@(list (filter (fn [x] (not (in (first x) vnam-mod))) vpar)))
                        vpar-add `(~@(list (filter (fn [x] (not (in (first x) vnam-mod))) vpar-add)))
                        vpar (+ vpar-res vpar-mod vpar-add )
                        ))))          )      )
  (setv vnam  (list (map first  vpar))
        vval  (list (map second vpar)))
  (for [v vnam] (if (= `(~v) p) (return p)))
  (if
    (and (symbol? p) (in p vnam) ) (get vval (.index vnam p))
    (if
      (not (coll? p))
      p
      (do
        (if (q-exp-fn? p 'symbol-macrolet)
            (do 
              (setv pa (cut p 0 2)
                    pb (cut p 2 None))
              ;; (print "pa" (hy-repr pa))
              ;; (print "pb" (hy-repr pb))
              (lif else-task (setv pb (else-task pb vpar else-task cont-walk-base)))
              (+
                pa
                (walk
                  (fn [p1]
                    (lif cont-walk-base
                         (cont-walk-base                p1 vpar else-task cont-walk-base)
                         (symbol-macrolet-cl-qexp-inner p1 vpar else-task cont-walk-base)))
                  identity pb)))
            (do
              (lif else-task (setv p (else-task p vpar else-task cont-walk-base)))
              (walk
                (fn [p1]
                  (lif cont-walk-base
                       (cont-walk-base                p1 vpar else-task cont-walk-base)
                       (symbol-macrolet-cl-qexp-inner p1 vpar else-task cont-walk-base)))
                identity p)))))))


  ;; (hy-repr
  ;;   (+
  ;;   (cut 
  ;;     '(sym-mac ((a b)(c d)) 1 2 3 4)
  ;;     0 2)
  ;;   (cut 
  ;;     '(sym-mac ((a b)(c d)) 1 2 3 4)
  ;;     2 None))
  ;;   )

  ;; (hy-repr
  ;;   (+ '()
  ;;      '(1)))
  
(defn symbol-macrolet-cl-qexp [code
                               &optional
                               else-task
                               cont-walk-base
                               ]
  (walk 
    (fn [p1] (symbol-macrolet-cl-qexp-inner
               p1
               (qexp-cl-var-pairs-colon-mod (get code 1))
               else-task
               cont-walk-base
               ))
    identity
    (cut code 2 None)
    ))


(defmacro symbol-macrolet [&rest body]
  `(do
     ~@(symbol-macrolet-cl-qexp
         `(symbol-macrolet ~@body )))
  )

;; (hy-repr
;; (symbol-macrolet-cl-qexp
;;   '(symbol-macrolet
;;       ((foo (+ 2 3)))
;;       (setv x 10)
;;       (+= x foo)
;;       x)
;; ))

;; (symbol-macrolet
;;       ((foo (+ 2 3)))
;;       (setv x 10)
;;       (+= x foo)
;;       x)


;; (symbol-macrolet ((om::%fail (print 20)))
;;      om::%fail)

;; (hy-repr
;;   (macroexpand
;;     '(symbol-macrolet ((om::%fail (print 20)))
;;        om::%fail)
;;   ))

;; (hy-repr
;;   (macroexpand
;;     '(symbol-macrolet ((a p))
;;        a)
;;   ))
