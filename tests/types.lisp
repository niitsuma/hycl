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

;;; Types SBCL derives, as opposed to types the programmer declaimed.
;;;
;;; The expander compiles each pure-CL DEFUN and reports what SBCL worked out,
;;; which is free and sound.  Two things are done with it: a return annotation
;;; where none was declaimed, and a refusal to hand Numba a function whose
;;; value a machine word cannot hold.

(defun derived-square (x)
  (declare (type double-float x))
  (* x x))

(defun derived-double (n)
  (declare (type integer n))
  (* n 2))

(deftest derived-return-float "<class 'float'>"
  (py-call str (py-getitem (py-attr (function derived-square) "__annotations__")
                           "return")))
(deftest derived-return-int "<class 'int'>"
  (py-call str (py-getitem (py-attr (function derived-double) "__annotations__")
                           "return")))

;;; (expt 2 (- n)) is 1/2^n in Common Lisp and zero in machine integers.  SBCL
;;; derives RATIONAL for it, so the speed declaration is refused and the
;;; function keeps its Lisp meaning rather than silently losing it.

(defun rational-valued (n)
  (declare (type integer n) (optimize (speed 3) (safety 0)))
  (expt 2 (- n)))

(deftest rational-not-promoted 'yes
  (if (equal (rational-valued 3) (/ 1 8)) 'yes 'no))

;;; a function of the same shape whose value does fit is still promoted
(defun integer-valued (n)
  (declare (type integer n) (optimize (speed 3) (safety 0)))
  (expt 2 n))

(deftest integer-still-promoted 8 (integer-valued 3))
