;; robust.lisp -- Common Lisp on the outside, numpy underneath
(py-import numpy)

(defun zscores (xs)
  "Each point's distance from the mean, in standard deviations."
  (let ((mu (numpy.mean xs))
        (sd (numpy.std xs)))
    (loop for x in xs collect (/ (- x mu) sd))))

(defun outliers (xs threshold)
  "The points whose z-score exceeds THRESHOLD."
  (loop for x in xs
        for z in (zscores xs)
        when (> (abs z) threshold)
          collect x))

(defun clean-mean (xs threshold)
  "The mean, after dropping the outliers."
  (let ((bad (outliers xs threshold)))
    (numpy.mean (remove-if (lambda (x) (member x bad)) xs))))
