(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected)
         (print (list 'pass ',name))
         (print (list 'FAIL ',name 'expected ,expected 'got got)))))

;; --- LOOP, the workhorse ---------------------------------------------
(deftest loop-collect '(1 4 9)
  (loop for i from 1 to 3 collect (* i i)))
(deftest loop-sum 55
  (loop for i from 1 to 10 sum i))
(deftest loop-when '(2 4)
  (loop for i from 1 to 5 when (evenp i) collect i))
(deftest loop-in 6
  (loop for x in '(1 2 3) sum x))
(deftest loop-while 16
  (let ((n 1)) (loop while (< n 10) do (setq n (* n 2))) n))

;; --- conditionals -----------------------------------------------------
(deftest cond-macro 'b (cond ((= 1 2) 'a) ((= 1 1) 'b) (t 'c)))
(deftest case-macro 'two (case 2 (1 'one) (2 'two) (otherwise 'other)))
(deftest when-macro 'yes (when (= 1 1) 'yes))
(deftest unless-macro 'no (unless (= 1 2) 'no))
(deftest and-or 3 (or nil (and 1 2 3)))

;; --- destructuring ----------------------------------------------------
(deftest destructuring-bind 6
  (destructuring-bind (a b c) '(1 2 3) (+ a b c)))
(deftest dolist-result 6
  (let ((s 0)) (dolist (x '(1 2 3) s) (setq s (+ s x)))))

;; --- places -----------------------------------------------------------
(deftest rotatef '(2 1)
  (let ((a 1) (b 2)) (rotatef a b) (list a b)))
(deftest psetq '(2 1)
  (let ((a 1) (b 2)) (psetq a b b a) (list a b)))

;; --- lambda / higher order -------------------------------------------
(deftest mapcar-lambda '(2 4 6)
  (mapcar (lambda (x) (* 2 x)) '(1 2 3)))
(deftest rest-args 10
  (progn (defun addup (&rest xs) (apply #'+ xs)) (addup 1 2 3 4)))
(deftest optional-arg 7
  (progn (defun inc-by (x &optional (d 1)) (+ x d)) (inc-by 5 2)))

;;; The ordinary path's arithmetic and predicates were specialised for the
;;; two-argument case, which is what a loop test is.  These pin the exactness
;;; and the chaining that the specialisation must not disturb.

(deftest div-exact-rational 'yes (if (equal (/ 1 3) (/ 2 6)) 'yes 'no))
(deftest div-canonical 2 (/ 6 3))
(deftest div-reciprocal 'yes (if (equal (/ 2) (/ 1 2)) 'yes 'no))
(deftest div-float-left 0.25 (/ 1.0 4))
(deftest div-float-right 0.25 (/ 1 4.0))
(deftest div-three 10 (/ 60 2 3))
(deftest div-three-rational 'yes (if (equal (/ 1 2 3) (/ 1 6)) 'yes 'no))

(deftest chain-lt-true t (< 1 2 3))
(deftest chain-lt-false nil (< 1 3 2))
(deftest chain-eq-true t (= 1 1 1))
(deftest chain-eq-false nil (= 1 1 2))
(deftest chain-ge t (>= 3 3 2))
(deftest compare-strings t (< "a" "b"))

;; the conditional over a total predicate is compiled without TRUTHY; these
;; check that the two spellings still agree, including the non-predicate case
(deftest if-over-predicate 'yes (if (< 1 2) 'yes 'no))
(deftest if-over-value 'yes (if 0 'yes 'no))          ; 0 is true in CL
(deftest if-over-nil 'no (if nil 'yes 'no))
(deftest while-over-predicate 5
  (let ((i 0)) (py-while (< i 5) (setq i (+ i 1))) i))
