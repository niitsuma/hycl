;; outliers.lisp -- Common Lisp on the outside, numpy underneath
(py-import numpy)

(defun outliers (xs threshold)
  "The points more than THRESHOLD standard deviations from the mean."
  (let ((mu (numpy.mean xs))
        (sd (numpy.std xs)))
    (loop for x in xs
          when (> (abs (/ (- x mu) sd)) threshold)
            collect x)))
