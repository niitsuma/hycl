;;;; Maxima, called as Lisp, during compilation.
;;;;
;;;; Maxima is itself a Common Lisp program, but far too large to compile
;;;; through this system.  It does not have to be: the expander can run it as
;;;; a subprocess and hand the answer to a macro.  What reaches Python is
;;;; ordinary arithmetic, so the compiled program needs neither Maxima nor a
;;;; Lisp to run.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(defmacro d/dx (expr var)
  "Differentiate at macroexpansion time.

Macro arguments arrive unexpanded, so the argument is expanded first; that is
what lets d/dx nest and produce a second derivative."
  (maxima-diff (macroexpand expr) var))

(defmacro simplify (expr)
  (maxima-simplify expr))

(defmacro expand-poly (expr)
  (maxima-expand expr))

;;; --- differentiation --------------------------------------------------

(defun cube-slope (x) (d/dx (* x x x) x))
(deftest diff-cube 27 (cube-slope 3))

(defun poly-slope (x) (d/dx (+ (* 2 (expt x 3)) (* 5 x) 7) x))
(deftest diff-poly 29 (poly-slope 2))

(defun sin-slope (x) (d/dx (sin x) x))
(deftest diff-sin 1.0 (sin-slope 0))

;; the derivative of a Gaussian, compiled to -2*x*exp(-x*x)
(defun gauss-slope (x) (d/dx (exp (- (* x x))) x))
(deftest diff-gauss 0.0 (gauss-slope 0))
(deftest diff-gauss-sign 'negative (if (< (gauss-slope 1.0) 0) 'negative 'positive))

;; second derivative, by nesting the macro
(defun cube-curvature (x) (d/dx (d/dx (* x x x) x) x))
(deftest second-derivative 24 (cube-curvature 4))

;;; --- simplification ---------------------------------------------------

(defun ratio (x) (simplify (/ (- (expt x 2) 1) (- x 1))))
(deftest simplified 6 (ratio 5))

(defun squared (x) (expand-poly (expt (+ x 1) 2)))
(deftest expanded 16 (squared 3))
