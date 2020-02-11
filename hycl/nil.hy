(import [collections.abc [Iterable]])

(defclass Nil/cl [] 
  (defn --init-- [self]
    (setv
      self.car self
      self.cdr self)))
(setv nil/cl (Nil/cl))
(defn null/cl? [x]
  (cond
    [(instance? Nil/cl x) True]
    [(= [] x) True]
    [(= (,) x) True]
    [(= '() x) True]
    [True False]))

;; ;;; take ConsPair from ohttps://github.com/algernon/adderall/blob/master/adderall/internal.hy
;; (defclass ConsPair [Iterable]
;;   "Construct a cons list.

;; A Python `list` is returned when the cdr is a `list` or `None`; otherwise, a
;; `ConsPair` is returned.

;; The arguments to `ConsPair` can be a car & cdr pair, or a sequence of objects to
;; be nested in `cons`es, e.g.

;;     (ConsPair car-1 car-2 car-3 cdr) == (ConsPair car-1 (cons car-2 (cons car-3 cdr)))
;; "
;;   (defn --new-- [cls &rest parts]
;;     (if (> (len parts) 2)
;;         (reduce (fn [x y] (ConsPair y x))
;;                 (reversed parts))
;;         ;; Handle basic car, cdr case.
;;         (do (setv car-part (-none-to-empty-or-list
;;                              (first parts)))
;;             (setv cdr-part (-none-to-empty-or-list
;;                              (if
;;                                (and (coll? parts)(> (len parts) 1))
;;                                (last parts)
;;                                ;;None
;;                                nil/cl
;;                                )))
;;             (cond
;;               [(instance? Nil/cl cdr-part)
;;                `(~car-part)]
;;               [(instance? hy.models.HyExpression cdr-part)
;;                `(~car-part ~@cdr-part)]
;;               [(tuple? cdr-part)
;;                (tuple (+ [car-part] (list cdr-part)))]
;;               [(list? cdr-part)
;;                     ;; Try to preserve the exact type of list
;;                     ;; (e.g. in case it's actually a HyList).
;;                (+ ((type cdr-part) [car-part]) cdr-part)]
;;               [True
;;                     (do
;;                       (setv instance (.--new-- (super ConsPair cls) cls))
;;                       (setv instance.car car-part)
;;                       (setv instance.cdr cdr-part)
;;                       instance)]))))
;;   (defn --hash-- [self]
;;     (hash [self.car, self.cdr]))
;;   (defn --eq-- [self other]
;;     (and (= (type self) (type other))
;;          (= self.car other.car)
;;          (= self.cdr other.cdr)))
;;   (defn --iter-- [self]
;;     (yield self.car)
;;     (if (coll? self.cdr) ;;(list? self.cdr)
;;         (for [x self.cdr] (yield x))
;;         (raise StopIteration))
;;     )
;;   (defn --repr-- [self]
;;     (.format "({} . {})" self.car self.cdr)))

;; (defn -none-to-empty-or-list [x]
;;   (cond
;;     ;;[(none? x) (list)]
;;     [(tuple? x) x]
;;     [(and (coll? x)
;;           (not (cons? x))
;;           (not (list? x)))
;;      (list x)]
;;     [True x]))

;; ;; A synonym for ConsPair
;; (setv cons ConsPair)

;; ;; (defun car (ls)
;; ;;   (first ls))

;; (defn car [z]
;;   (or (getattr z "car" None)
;;       (-none-to-empty-or-list (first z))))

;; (defn cdr [z]
;;   (or (getattr z "cdr" None)
;;       (cond
;;         [(instance? range z) (cut z 1)]
;;         [(iterator? z) (rest z)]
;;         [True ;;(or (tuple? z) (list? z))
;;              ((type z) (list (rest z)))]
;;         ;;[True (rest z)]
;;       ;;  ;; Try to preserve the exact type of list
;;       ;;  ;; (e.g. in case it's actually a HyList).
;;         ;;((type z) (list (rest z)))
;;         )))


;; (defn cons? [a]
;;   (cond [(null/cl? a) False]
;;         [(instance? ConsPair a) True]
;;         ;;[(coll? a) (not (empty? a)) True]
;;         [(or (list? a) (tuple? a) ) (not (empty? a)) True]
;;         [True False])
;;   ;; (if (or (and
;;   ;;           (list? a)
;;   ;;           (not (empty? a)))
;;   ;;         (instance? ConsPair a))
;;   ;;     True
;;   ;;     False))
;;   )
