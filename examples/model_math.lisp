;;;; The parts of the model that are easier to derive than to write.
;;;;
;;;; This file is Common Lisp; main.py imports it as if it were Python.

(py-import torch)

(defmacro d/dx (expr var)
  (maxima-diff (macroexpand expr) var))

;;; A custom activation whose backward pass Maxima derives.  Torch never
;;; builds a tape for it: the gradient is arithmetic, decided before the
;;; program started.

(defmacro defactivation (name (x) expr)
  (let ((slope (maxima-diff expr x)))
    `(setq ,name
       (py-class ,(string name)
                 (list torch.autograd.Function)
                 "forward"
                 (py-staticmethod
                   (lambda (ctx ,x)
                     (py-method ctx "save_for_backward" ,x)
                     ,expr))
                 "backward"
                 (py-staticmethod
                   (lambda (ctx grad)
                     (let ((,x (py-getitem (py-attr ctx "saved_tensors") 0)))
                       (* grad ,slope))))))))

;; swish(x) = x * sigmoid(x)
(defactivation swish (x) (/ x (+ 1 (exp (- x)))))

;;; The same function and its derivative as ordinary scalars, with the types
;;; declared the Common Lisp way so Python sees annotations.

(declaim (ftype (function (double-float) double-float) swish-scalar))
(defun swish-scalar (x)
  (declare (type double-float x))
  (/ x (+ 1 (exp (- x)))))

(declaim (ftype (function (double-float) double-float) swish-slope))
(defun swish-slope (x)
  (declare (type double-float x))
  (d/dx (/ x (+ 1 (exp (- x)))) x))
