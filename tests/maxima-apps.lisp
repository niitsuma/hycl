;;;; Four things a computer algebra system can do for a program while that
;;;; program is being compiled.

(py-import torch)

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; ------------------------------------------------------------------ 1
;;; Analytic gradients.
;;;
;;; Autograd builds a tape and differentiates at run time.  Here the
;;; derivative is known before the program starts, so the backward pass is
;;; straight-line arithmetic and the tape is never built.

(defmacro defdiffable (name (var) expr)
  "Define a torch.autograd.Function whose backward pass Maxima derived."
  (let ((slope (maxima-diff expr var)))
    `(setq ,name
       (py-class ,(string name)
                 (list torch.autograd.Function)
                 "forward"
                 (py-staticmethod
                   (lambda (ctx ,var)
                     (py-method ctx "save_for_backward" ,var)
                     ,expr))
                 "backward"
                 (py-staticmethod
                   (lambda (ctx grad)
                     (let ((,var (py-getitem (py-attr ctx "saved_tensors") 0)))
                       (* grad ,slope))))))))

(defdiffable quartic (x) (+ (* 3 (expt x 4)) (* 2 x) 1))

(defun analytic-grad (v)
  (let ((x (py-call torch.tensor v :requires_grad py-true)))
    (py-method (py-method quartic "apply" x) "backward")
    (py-method (py-attr x "grad") "item")))

(defun autograd-grad (v)
  (let ((x (py-call torch.tensor v :requires_grad py-true)))
    (py-method (+ (* 3 (expt x 4)) (* 2 x) 1) "backward")
    (py-method (py-attr x "grad") "item")))

;; 12x^3 + 2, which is 98 at x = 2
(deftest analytic-gradient 98.0 (analytic-grad 2.0))
(deftest agrees-with-autograd 'yes
  (if (< (abs (- (analytic-grad 2.0) (autograd-grad 2.0))) 1e-4) 'yes 'no))

;;; ------------------------------------------------------------------ 2
;;; Common subexpression elimination, done by Maxima.
;;;
;;; OPTIMIZE returns a block of temporaries, which is a LET* and compiles to
;;; one.

(defmacro optimized (expr)
  (maxima-optimize expr))

(defun repeated (x)
  (optimized (+ (* (sin x) (sin x)) (* 3 (sin x)) 1)))

(deftest cse-value 1.0 (repeated 0))
(deftest cse-value-2 'close
  (if (< (abs (- (repeated 1.0) 4.2325)) 0.001) 'close 'off))

;;; ------------------------------------------------------------------ 3
;;; Series expansion: a fast approximation compiled into the program.

(defmacro taylor-poly (expr var point order)
  (maxima-taylor expr var point order))

(defun exp-approx (x) (taylor-poly (exp x) x 0 6))

(deftest taylor-at-zero 1 (exp-approx 0))
(deftest taylor-accuracy 'close
  (if (< (abs (- (exp-approx 0.5) 1.6487212)) 1e-5) 'close 'off))

;;; ------------------------------------------------------------------ 4
;;; Compile-time algebra as a check rather than a generator.

(defmacro solve-for (var equation)
  (maxima-solve equation var))

(defun linear-root (a b) (solve-for x (= (+ (* a x) b) 0)))
(deftest solved -2 (linear-root 3 6))

(defmacro assert-identity (a b)
  "Fail the compilation unless Maxima can prove A = B."
  (if (maxima-provable-p a b)
      `'verified
      (error "not an identity: ~s = ~s" a b)))

(deftest identity-holds 'verified
  (assert-identity (expt (+ a b) 2) (+ (* a a) (* 2 a b) (* b b))))
