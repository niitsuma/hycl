(py-import torch)

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;; --- context managers -------------------------------------------------
(defun inside-no-grad ()
  (py-with ((g (torch.no-grad))) (if (torch.is-grad-enabled) 'on 'off)))
(defun outside-no-grad () (if (torch.is-grad-enabled) 'on 'off))
(deftest py-with-enters 'off (inside-no-grad))
(deftest py-with-exits 'on (outside-no-grad))

;; --- defstruct --------------------------------------------------------
(defstruct point x y)

(defun move (p dx)
  (setf (point-x p) (+ (point-x p) dx))
  p)

(deftest struct-make 3 (point-x (make-point :x 3 :y 4)))
(deftest struct-setf 8 (point-x (move (make-point :x 3 :y 4) 5)))
(deftest struct-pred t (point-p (make-point :x 1 :y 2)))
(deftest struct-default nil (point-y (make-point :x 1)))
(deftest struct-copy 7 (point-x (copy-point (make-point :x 7 :y 0))))
