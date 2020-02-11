
(import [hy.contrib.walk [postwalk]])

;; (import [adderall.internal [*]])
;; (import [adderall.dsl [*]])
;; (require [adderall.dsl [*]])
;; (import [hydiomatic.core [*]])
;; (require [hydiomatic.macros [*]])
;; (defn simplifypost [expr &optional [rules rules/default]]
;;   (postwalk (fn [x] (simplify-step* x rules)) expr))


;;(import [gasync.core [q-exp-fn?]])

(import [hycl.nil [*]])
(import [hycl.core [*]])


(setv element-renames
      {
       'nil 'nil/cl
       'null 'null/cl?
       'if 'if/cl
       'let 'let/cl
       'setq 'setv
       }
      )

(defn q-element-renames? [s] (and (symbol? s)  (in s element-renames)))
(defn q-element-cl-replace [p]  (if (q-element-renames? p)  (get element-renames p) p))
(defn q-exp-cl-rename-deep [p] (postwalk q-element-cl-replace p))

;; (import [hy.contrib.hy-repr [hy-repr hy-repr-register]])

;; (defun testfn (x y)
;;   (if x y (+ 3 y))
;;   )

;; (testfn 1 2)

(defmacro defun [name arg &rest code]
  ;;(print name )
  ;;(print name arg (hy-repr code))
  `(defn ~name [~@arg]
     ~@(lfor p code (q-exp-cl-rename-deep p)))
     )

