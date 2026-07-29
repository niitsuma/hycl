;;;; Macros from Paul Graham's _On Lisp_, run through hyclb.
;;;; Each form prints PASS or FAIL so the harness can count them.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected)
         (print (list 'pass ',name))
         (print (list 'fail ',name 'expected ,expected 'got got)))))

;;; --- ch.11: classic macros -------------------------------------------

(defmacro while2 (test &body body)
  `(do () ((not ,test)) ,@body))

(defun count-down (n)
  (let ((acc nil))
    (while2 (> n 0)
      (setq acc (cons n acc))
      (setq n (- n 1)))
    acc))

(deftest while2 '(1 2 3) (count-down 3))

;;; --- ch.14: anaphoric macros -----------------------------------------

(defmacro aif (test then &optional else)
  `(let ((it ,test)) (if it ,then ,else)))

(defmacro awhen (test &body body)
  `(aif ,test (progn ,@body)))

(defmacro aand (&rest args)
  (cond ((null args) t)
        ((null (cdr args)) (car args))
        (t `(aif ,(car args) (aand ,@(cdr args))))))

(defmacro awhile (expr &body body)
  `(do ((it ,expr ,expr)) ((not it)) ,@body))

(defun probe (x) (aif (car x) (+ it 100) 'none))
(deftest aif-hit 105 (probe '(5 6)))
(deftest aif-miss 'none (probe nil))

(defun awhen-test (x) (awhen (cdr x) (car it)))
(deftest awhen 2 (awhen-test '(1 2 3)))

(deftest aand 4 (aand '(1 2 3) (cdr it) (+ 2 (car it))))

(defun drain (lst)
  (let ((n 0))
    (awhile (car lst)
      (setq n (+ n it))
      (setq lst (cdr lst)))
    n))
(deftest awhile 6 (drain '(1 2 3)))

;;; --- ch.10: variable capture, gensyms --------------------------------

(defmacro with-gensyms (syms &body body)
  `(let ,(mapcar (lambda (s) `(,s (gensym))) syms) ,@body))

(defmacro our-for ((var start stop) &body body)
  (with-gensyms (gstop)
    `(do ((,var ,start (1+ ,var))
          (,gstop ,stop))
         ((> ,var ,gstop))
       ,@body)))

(defun triangle (n)
  (let ((acc 0))
    (our-for (i 1 n) (setq acc (+ acc i)))
    acc))
(deftest with-gensyms 15 (triangle 5))

;;; --- ch.12: generalized variables ------------------------------------

(defmacro toggle2 (place)
  `(setf ,place (not ,place)))

(defun toggling ()
  (let ((flag nil))
    (toggle2 flag)
    flag))
(deftest toggle t (toggling))

(defun counting ()
  (let ((n 0))
    (incf n 5)
    (decf n 2)
    n))
(deftest incf-decf 3 (counting))

;;; --- ch.5/ch.15: functions returning functions -----------------------

(defun compose2 (f g)
  (lambda (x) (funcall f (funcall g x))))

(deftest compose 9 (funcall (compose2 (lambda (x) (* x 3))
                                      (lambda (x) (+ x 1)))
                            2))

;;; --- recursion and non-local exit ------------------------------------

(defun find-first-even (lst)
  (dolist (x lst)
    (if (= 0 (mod x 2)) (return-from find-first-even x)))
  nil)
(deftest return-from 4 (find-first-even '(1 3 4 5)))

(defun my-length (lst)
  (labels ((walk (l n) (if (null l) n (walk (cdr l) (1+ n)))))
    (walk lst 0)))
(deftest labels 3 (my-length '(a b c)))

;;; --- structure and identity ------------------------------------------

(deftest eq-symbols t (eq 'foo 'foo))
(deftest equal-lists t (equal '(1 (2 3)) '(1 (2 3))))
(deftest dotted '(1 . 2) (cons 1 2))

;;; --- CL truth, not Python truth --------------------------------------

(deftest zero-is-true 'yes (if 0 'yes 'no))
(deftest empty-list-is-false 'no (if nil 'yes 'no))
