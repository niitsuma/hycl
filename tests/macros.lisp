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
