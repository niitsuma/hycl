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

;;; (:tolerance EPS) loosens the numeric comparisons.  Necessary even for an
;;; exact-sounding task: the model answers (* pi r r), and pi times a float
;;; can never hit a four-digit literal exactly.  With samples instead of
;;; specifications it becomes regression -- see examples/llm_macro.lisp,
;;; where thirteen unlabelled points of a sine come back as (sin x).

(defllm circle-area (r)
  "the area of a circle of radius r"
  (:tolerance 1e-3)
  (:check (1.0) 3.1416)
  (:check (2.0) 12.5664))

(deftest circle-area-r10 t
  (if (< (abs (- (circle-area 10.0) 314.1592653589793)) 0.1) t nil))

;;; ASK-LLM is the unchecked door, and narrow on purpose: the answer is a
;;; string, so a wrong one makes the program wrong rather than broken.  It
;;; is a constant by the time Python sees it -- the model is not there to be
;;; asked again -- and two occurrences of one question give one answer.

(defvar *capital*
  (ask-llm "Which city is the capital of Japan?  Reply with the city name alone."
           :max-tokens 20))

(deftest ask-llm-answers t
  (if (>= (py-method (string-upcase *capital*) "find" "TOKYO") 0) t nil))

(deftest ask-llm-is-a-constant t (if (stringp *capital*) t nil))

;; asked twice, answered once: the expander memoises, so these are the same
;; string rather than two samples that might disagree
(deftest ask-llm-memoised t
  (if (string= (ask-llm "Name one primary colour.  One word.")
               (ask-llm "Name one primary colour.  One word."))
      t nil))

;;; The other two doors return code rather than data, and each is checked by
;;; the compiler of the language it is written in.  One request, asked three
;;; ways: x*y plus the numeric value of pi.

(defun lisp-arm (x y)
  ;; SBCL compiles this answer here; :FREE is what lets it call every other
  ;; name undefined.  It comes back as (+ (* x y) pi).
  (ask-llm-form "x times y, plus the numeric value of pi" :free (x y)))

(defun python-arm (x y)
  ;; CPython parses this one and frompy translates it.  It comes back as
  ;; math.pi, and the import it needs is read off the dotted name -- an
  ;; expression has no room to say `import math` for itself.
  (ask-llm-python "x*y plus the numeric value of pi"))

(defmacro defclose (name expected form)
  `(let ((got ,form))
     (if (< (abs (- got ,expected)) 1e-9) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(defclose ask-llm-form-computes (+ 12.0 pi) (lisp-arm 3.0 4.0))
(defclose ask-llm-python-computes (+ 12.0 pi) (python-arm 3.0 4.0))
(defclose ask-llm-arms-agree 0.0 (- (lisp-arm 2.5 4.0) (python-arm 2.5 4.0)))
