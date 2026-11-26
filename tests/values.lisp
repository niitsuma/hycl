;;;; Multiple values.
;;;;
;;;; Python returns one object.  The values after the first are left with
;;;; the runtime by the form that produced them and taken by the form that
;;;; asks for them -- and only by that one: a function that returns a single
;;;; value must not hand on what an earlier VALUES left behind.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; --- the division functions give a quotient and a remainder -------------

(deftest floor-gives-two '(3 1) (multiple-value-bind (q r) (floor 7 2) (list q r)))
(deftest floor-of-a-negative '(-4 1) (multiple-value-bind (q r) (floor -7 2) (list q r)))
(deftest truncate-of-a-negative '(-3 -1) (multiple-value-bind (q r) (truncate -7 2) (list q r)))
(deftest ceiling-gives-two '(4 -1) (multiple-value-bind (q r) (ceiling 7 2) (list q r)))
(deftest round-to-even '((2 1) (4 -1) (2 -1/2))
  (list (multiple-value-list (round 5 2)) (multiple-value-list (round 7 2))
        (multiple-value-list (round 3/2))))
(deftest floor-of-a-float '(3 0.5) (multiple-value-list (floor 3.5)))
(deftest floor-with-a-float-divisor '(2 1.5) (multiple-value-list (floor 7.5 3)))
(deftest one-argument '(7 0) (multiple-value-list (floor 7)))
;; exact, however large: the quotient is not computed in floating point
(deftest large-integers-are-exact '(33333333333333333333 1)
  (multiple-value-list (floor 100000000000000000000 3)))
(deftest the-first-value-alone 3 (floor 7 2))
(deftest in-arithmetic 4 (+ 1 (floor 7 2)))

;;; --- VALUES and its consumers --------------------------------------------

(defun two (a b) (values a b))
(defun three () (values 1 2 3))
(deftest values-through-a-function '(1 2) (multiple-value-bind (a b) (two 1 2) (list a b)))
(deftest fewer-names-than-values '(1 2) (multiple-value-bind (a b) (three) (list a b)))
(deftest more-names-than-values '(1 2 nil) (multiple-value-bind (a b c) (two 1 2) (list a b c)))
(deftest multiple-value-list '(1 2 3) (multiple-value-list (three)))
(deftest of-one-value '(5) (multiple-value-list (+ 2 3)))
(deftest nth-value '(1 3 nil) (list (nth-value 0 (three)) (nth-value 2 (three)) (nth-value 5 (three))))
(deftest multiple-value-call '(1 2 1 2 3)
  (multiple-value-call #'list (two 1 2) (three)))
(deftest multiple-value-call-adds 10 (multiple-value-call #'+ (floor 7 2) (three)))
(deftest values-list '(4 5) (multiple-value-list (values-list '(4 5))))
(deftest multiple-value-prog1 '(1 2 3)
  (multiple-value-list (multiple-value-prog1 (three) (two 8 9))))
(deftest multiple-value-setq '(3 1)
  (let ((q 0) (r 0)) (multiple-value-setq (q r) (floor 7 2)) (list q r)))
(deftest gethash-says-whether '((1 t) (nil nil) (0 nil))
  (let ((h (make-hash-table)))
    (setf (gethash 'a h) 1)
    (list (multiple-value-list (gethash 'a h)) (multiple-value-list (gethash 'b h))
          (multiple-value-list (gethash 'b h 0)))))

;;; --- what an earlier form left behind is nobody else's --------------------

(defun one-after-two (x) (two x 99) (+ x 1))
(deftest a-single-value-is-single '(6 nil)
  (multiple-value-bind (a b) (one-after-two 5) (list a b)))
(defun quotient-plus-one (n) (+ 1 (floor n 2)))
(deftest also-after-floor '(4 nil)
  (multiple-value-bind (a b) (quotient-plus-one 7) (list a b)))
(deftest taken-once '((3 1) (5 nil))
  (list (multiple-value-list (floor 7 2)) (multiple-value-bind (a b) 5 (list a b))))
(deftest a-plain-value-in-between '(nil)
  (progn (two 1 2) (multiple-value-list nil)))
