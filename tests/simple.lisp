

(defun testfn (x y)
  (setq y (* x y))
  (+ x y))

(defun testfn2 (x y)
  (setq y (+ x y))
  (* x y))


