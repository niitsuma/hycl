;;;; Generators written in Common Lisp.
;;;;
;;;; YIELD cannot cross a function boundary, so it is the sharpest test of the
;;;; rule that binding forms and control structures expand inline.  A LET
;;;; compiled to an applied lambda, or a TAGBODY compiled to mutually calling
;;;; functions, would break every one of these.

(py-import asyncio)

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;; yield through a TAGBODY: dotimes is a state machine, and the generator
;; suspends inside it
(defun counter (n)
  (dotimes (i n) (py-yield i)))
(deftest yield-in-dotimes '(0 1 2) (from-py (py-list (counter 3))))

;; yield through LET
(defun squares (lst)
  (dolist (x lst)
    (let ((y (* x x)))
      (py-yield y))))
(deftest yield-in-let '(1 4 9) (from-py (py-list (squares '(1 2 3)))))

;; yield through LOOP, which is also a tagbody
(defun evens (n)
  (loop for i from 0 to n
        when (evenp i)
        do (py-yield i)))
(deftest yield-in-loop '(0 2 4) (from-py (py-list (evens 5))))

;; yield inside a HANDLER-CASE, which is a try
(defun guarded (lst)
  (dolist (x lst)
    (handler-case (py-yield (/ 10 x))
      (error (e) (py-yield 'undefined)))))
(deftest yield-in-handler 3 (length (from-py (py-list (guarded '(1 2 5))))))

;; delegation
(defun both (a b)
  (py-yield-from a)
  (py-yield-from b))
(deftest yield-from '(1 2 3 4)
  (from-py (py-list (both (py-list '(1 2)) (py-list '(3 4))))))

;; laziness: an unbounded generator, consumed in part
(defun naturals ()
  (let ((i 0))
    (loop (py-yield i) (incf i))))
(defun take (n gen)
  (let ((out nil))
    (dotimes (k n) (push (py-method gen "__next__") out))
    (reverse out)))
(deftest infinite-generator '(0 1 2 3) (take 4 (naturals)))

;; async
(defun-async slowly (x)
  (py-await (py-call asyncio.sleep 0))
  (* x 2))
(deftest async-defun 14 (py-call asyncio.run (slowly 7)))

;; decorators
(py-import functools)

(defun twice (f)
  (lambda (x) (* 2 (py-call f x))))

(defun-decorated (twice) tripled (x) (* 3 x))
(deftest decorator 30 (tripled 5))
