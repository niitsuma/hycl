;;;; A language model in Maxima's seat.
;;;;
;;;; model_math.lisp consults Maxima while the program compiles; this file
;;;; consults a local language model the same way.  The difference is trust:
;;;; algebra is accepted, a sampled answer never is.  DEFLLM sends the
;;;; description to the model, evaluates the returned expression against its
;;;; :CHECK clauses in SBCL, feeds a failure back for another attempt, and
;;;; only an answer that passes becomes a DEFUN.  The compiled program calls
;;;; ordinary Python and depends on no model at all.
;;;;
;;;; Needs a CLI that prints one completion for one prompt -- `ask-local`
;;;; by default; see the README for the exact contract.  Run with:
;;;;
;;;;   python -c "from hyclb.api import cl_load, new_module; \
;;;;              m = new_module('llm'); cl_load('examples/llm_macro.lisp', m); m.main()"

;; The description is the program; the checks are the contract.  This one
;; comes back as (max lo (min x hi)).
(defllm clamp (x lo hi)
  "x limited to the closed interval [lo, hi]"
  (:check (5 0 10) 5)
  (:check (-3 0 10) 0)
  (:check (42 0 10) 10))

;; Easier to describe than to write: the model knows the Gregorian rules,
;; and the checks pin the two ways to get February wrong.
(defllm days-in-month (m y)
  "the number of days in month m (1 to 12) of Gregorian year y"
  (:check (2 2024) 29)
  (:check (2 1900) 28)
  (:check (2 2000) 29)
  (:check (9 2021) 30)
  (:check (12 1999) 31))

;; Symbolic regression, one prompt long.  Thirteen samples of an unnamed
;; function, a tolerance, and no other hint: (:tolerance 0.01) turns every
;; check into a fitted data point, so the instruction amounts to "find the
;; function underneath these numbers".  Nothing here says sine -- the model
;; recognises the shape and comes back with (sin x).  Had it answered with a
;; polynomial instead, the checks would have judged the fit the same way.
(defllm recovered-f (x)
  "a smooth closed-form function fitting the sampled points"
  (:tolerance 0.01)
  (:check (0.0) 0.0)
  (:check (0.5236) 0.5)
  (:check (1.0472) 0.866)
  (:check (1.5708) 1.0)
  (:check (2.0944) 0.866)
  (:check (2.618) 0.5)
  (:check (3.1416) 0.0)
  (:check (3.6652) -0.5)
  (:check (4.1888) -0.866)
  (:check (4.7124) -1.0)
  (:check (5.236) -0.866)
  (:check (5.7596) -0.5)
  (:check (6.2832) 0.0))

(defun main ()
  (print (list 'clamped (clamp 99 0 7)))
  (print (list 'february 2100 'has (days-in-month 2 2100) 'days))
  ;; the recovered function against the sine the samples were taken from,
  ;; on a hundred points the model never saw
  (py-import math)
  (let ((worst 0.0))
    (dotimes (i 100)
      (let* ((x (/ (* i 6.29) 100))
             (d (abs (- (recovered-f x) (math.sin x)))))
        (when (> d worst) (setq worst d))))
    (print (list 'recovered-f 'max-error-vs-sin worst)))
  ;; inputs the model never saw, checked against Python's own calendar
  (py-import calendar)
  (let ((ok t))
    (dotimes (m 12)
      (dolist (y (list 1999 2000 2023 2024 2100))
        (unless (= (days-in-month (+ m 1) y)
                   (py-getitem (calendar.monthrange y (+ m 1)) 1))
          (setq ok nil))))
    (print (list 'agrees-with-python-calendar ok))
    ok))
