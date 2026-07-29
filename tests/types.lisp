(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(declaim (ftype (function (integer string) double-float) scale))
(defun scale (n label)
  (declare (type integer n) (type string label))
  (* 1.5 n))

(py-import-as typing ty)
(deftest annotations-present '("int" "str" "float")
  (let ((a (py-attr scale "__annotations__")))
    (list (py-attr (py-getitem a "n") "__name__")
          (py-attr (py-getitem a "label") "__name__")
          (py-attr (py-getitem a "return") "__name__"))))

(deftest still-runs 3.0 (scale 2 "x"))

;; slot types, written the Common Lisp way
(defclass sample () ((n :type integer :initform 0)
                     (label :type string :initform "")))

(deftest slot-annotations '("int" "str")
  (let ((a (py-attr sample "__annotations__")))
    (list (py-attr (py-getitem a "n") "__name__")
          (py-attr (py-getitem a "label") "__name__"))))
