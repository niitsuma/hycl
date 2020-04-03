
(import [nose.tools [eq_  assert-equal assert-not-equal]])


(import  [hyclb.core [*]])
(require [hyclb.core [*]])

(import   [hyclb.cl4hy [*]])
(require  [hyclb.cl4hy [*]])

;;(import  [hyclb.models [hyclvector hycllist]] )


(defn assert-all-equal [&rest tests]
  (reduce (fn [x y] (assert-equal x y) y)
          tests)
  None)

(defn test-internal []

  ;; (eq_
  ;;   (clisp.readtable.read_str "#(1 2 3)")
  ;;   (cl_eval_hy_str "(vector 1 2 3)")
  ;;   ;;[1 2 3]
  ;;   )

  (eq_
    (clisp.readtable.read_str "(1 . 2)")
    (cons 1 2)
    )
  
  (eq_
    (clisp.readtable.read_str "(1 2 . 3)")
    (cons 1 (cons 2 3))
    )

  ;; (eq_
  ;;   (from-pipe-symbol-str "c|aa|bb")
  ;;   "caabb")
  ;; (eq_
  ;;   (from-pipe-symbol-str "CC|aAa|BB")
  ;;   "ccaAabb")
  
  ;; (eq_
  ;;   (maybe-pipe-symbol-str "AVVAA")
  ;;   "avvaa")
  ;; (eq_
  ;;   (maybe-pipe-symbol-str "aXa")
  ;;   "aXa")

  (eq_
    (clisp.readtable.read_str "|aBaC|?")
    'aBaC?   )
  (eq_
    (clisp.readtable.read_str "|ABCD|")
    'ABCD)
  (eq_
    (clisp.readtable.read_str "|ABCD|?")
    'ABCD?)

  (eq_
    (clisp.readtable.read_str "abcd?")
    'abcd?)
  
  (eq_
    (to-pipe-symbol (hy.models.HySymbol "AA"))
    (hy.models.HySymbol "AA"))

  (eq_
    (to-pipe-symbol (hy.models.HySymbol "aa"))
    (hy.models.HySymbol "|aa|"))

  (eq_
    (to-pipe-symbol (hy.models.HySymbol "aXa"))
    (hy.models.HySymbol "|aXa|"))

  (eq_
    (to-pipe-symbol (hy.models.HySymbol "AA?"))
    (hy.models.HySymbol "AA?"))

  (eq_
    (to-pipe-symbol (hy.models.HySymbol "aa?"))
    (hy.models.HySymbol "|aa|?"))

  (eq_
    (to-pipe-symbol (hy.models.HySymbol "aXa?"))
    (hy.models.HySymbol "|aXa|?"))

  (eq_
    (cl_eval_hy_qexpr '(list 'aa 'AA 'aBCd))
    '(aa AA aBCd) )

  (eq_
    (hy2cl-symbol-deep
      '(list/cl 12 3)
      ;;element-renames-reverse
      )
    '(LIST 12 3))
  
  )


(defn test-defuncl []
  (defun testfn (x y)
    (setq y (+ 3 y))
    (+ x y))
  (eq_
    (testfn 12 35)
    50
    )

  (defun/global testfngl1 (x y)
    (setq y (+ 3 y))
    (+ x y))
  (eq_
    (testfngl1 12 35)
    50
    )

  (defun testcldbind ()
    (let ((l (list 1 2 3)))
      (destructuring-bind (x y z) l
        (+ x y z))))
  (eq_
    (testcldbind)
    6
    )

  )

