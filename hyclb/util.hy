
(import [hy.contrib.walk [postwalk]])

;; (import [adderall.internal [*]])
;; (import [adderall.dsl [*]])
;; (require [adderall.dsl [*]])
;; (import [hydiomatic.core [*]])
;; (require [hydiomatic.macros [*]])
;; (defn simplifypost [expr &optional [rules rules/default]]
;;   (postwalk (fn [x] (simplify-step* x rules)) expr))


;;(import [gasync.core [q-exp-fn?]])


(import [hyclb.core [*]])


(setv element-renames
      {
       'nil 'nil/cl
       'null 'null/cl
       'if 'if/cl
       'let 'let/cl
       'setq 'setv
       'setf 'setv       
       'atom 'atom/cl
       't True
       }
      )

;;(defn q-element-renames? [p] (and (symbol? p)  (in p element-renames)))
(defn q-element-cl-replace [p]
  (if (and (symbol? p)  (in p element-renames))
      (get element-renames p) p))
(defn q-exp-cl-rename-deep [p] (postwalk q-element-cl-replace p))


;; (defmacro labels [name arg &rest code]
;;   `(defn ~name [~@arg]
;;      ~@(lfor p code (q-exp-cl-rename-deep p)))
;;      )

(defmacro defun/simple [name arg &rest code]
  `(defn ~name [~@arg]
     ~@(lfor p code (q-exp-cl-rename-deep p)))
     )

