;;;; Places: what INCF, DECF, PUSH and POP change, and what MAKE-ARRAY makes.
;;;;
;;;; INCF and DECF stay on the expansion frontier so that (incf i) compiles
;;;; to an addition.  That left two cases the translation did not cover: a
;;;; special variable changed inside a function, which Python takes for a
;;;; local unless told otherwise, and a place that is not a variable at all.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; --- a special variable, changed inside a function ----------------------

(defvar *count* 0)
(defvar *stack* '())

(defun bump () (incf *count*))
(defun bump-by (n) (incf *count* n))
(defun drop () (decf *count*))
(defun keep (x) (push x *stack*))
(defun take () (pop *stack*))

(deftest incf-of-a-special 1 (bump))
(deftest incf-with-a-delta 11 (bump-by 10))
(deftest decf-of-a-special 10 (drop))
(deftest the-variable-was-changed 10 *count*)
(deftest push-onto-a-special '(2 1) (progn (keep 1) (keep 2)))
(deftest pop-from-a-special 2 (take))
(deftest and-it-is-shorter '(1) *stack*)

;;; --- a place that is not a variable --------------------------------------

(deftest incf-of-an-element '(1 5 3)
  (let ((v (list 1 2 3)))
    (incf (nth 1 v) 3)
    v))

(deftest decf-of-an-array-element 7
  (let ((a (make-array 3 :initial-element 10)))
    (decf (aref a 2) 3)
    (aref a 2)))

(deftest incf-returns-the-new-value 11
  (let ((a (make-array 1 :initial-element 10)))
    (incf (aref a 0))))

;; the subforms of the place are evaluated once
(defvar *evaluations* 0)
(defun next-index () (incf *evaluations*) 1)

(deftest subforms-are-evaluated-once '(12 1)
  (let ((v (list 10 10 10)))
    (incf (nth (next-index) v) 2)
    (list (second v) *evaluations*)))

;;; --- MAKE-ARRAY takes its keywords ---------------------------------------

(deftest initial-element 7 (aref (make-array 3 :initial-element 7) 2))
(deftest element-type-is-accepted 0
  (aref (make-array 2 :element-type 'fixnum :initial-element 0) 1))
(deftest initial-contents 30 (aref (make-array 3 :initial-contents '(10 20 30)) 2))
(deftest two-dimensions 5
  (let ((m (make-array '(2 3) :initial-element 0)))
    (setf (aref m 1 2) 5)
    (+ (aref m 1 2) (aref m 0 2))))
(deftest rows-are-not-shared 0
  (let ((m (make-array '(2 2) :initial-element 0)))
    (setf (aref m 0 0) 9)
    (aref m 1 0)))
(deftest two-dimensional-contents 4
  (aref (make-array '(2 2) :initial-contents '((1 2) (3 4))) 1 1))
