(ql:quickload "alexandria")
(ql:quickload "iterate")
(ql:quickload "anaphora")

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected)
         (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;; alexandria
(deftest when-let 10
  (alexandria:when-let (x 5) (* 2 x)))
(deftest if-let 'none
  (alexandria:if-let (x nil) (* 2 x) 'none))
(deftest with-gensyms 3
  (alexandria:with-gensyms (a) (let ((b 3)) b)))
(deftest switch 'two
  (alexandria:switch (2 :test #'eql) (1 'one) (2 'two)))

;; iterate
(deftest iterate-collect '(1 4 9)
  (iterate:iter (iterate:for i from 1 to 3) (iterate:collect (* i i))))
(deftest iterate-sum 55
  (iterate:iter (iterate:for i from 1 to 10) (iterate:sum i)))

;; anaphora
(deftest anaphora-aif 105
  (anaphora:aif (car '(5)) (+ anaphora:it 100) 'none))
