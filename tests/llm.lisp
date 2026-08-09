;;;; A language model in Maxima's seat.
;;;;
;;;; DEFLLM asked the local model for each body while this file compiled, and
;;;; admitted the answer only after it passed its :CHECK clauses in SBCL.
;;;; What runs here is the translated Python, so these tests are the second
;;;; half of the bargain: the expansion-time checks proved the Lisp, these
;;;; prove the translation -- on inputs the model never saw.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; The description is the program; the checks are the contract.

(defllm clamp (x lo hi)
  "x limited to the closed interval [lo, hi]"
  (:check (5 0 10) 5)
  (:check (-3 0 10) 0)
  (:check (42 0 10) 10))

(deftest clamp-inside 4 (clamp 4 1 8))
(deftest clamp-below 1 (clamp -100 1 8))
(deftest clamp-above 8 (clamp 99 1 8))

;;; Easier to describe than to write: the model knows the Gregorian rules,
;;; and the checks pin the two ways to get February wrong.

(defllm days-in-month (m y)
  "the number of days in month m (1 to 12) of Gregorian year y"
  (:check (2 2024) 29)
  (:check (2 1900) 28)
  (:check (2 2000) 29)
  (:check (9 2021) 30)
  (:check (12 1999) 31))

(deftest days-january 31 (days-in-month 1 2026))
(deftest days-leap-february 29 (days-in-month 2 2028))
(deftest days-plain-february 28 (days-in-month 2 2027))
(deftest days-april 30 (days-in-month 4 2026))
(deftest days-century 28 (days-in-month 2 2100))
