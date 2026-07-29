;;;; Equations of motion, derived by Maxima while the program compiles.
;;;;
;;;; Physics is written down as a Lagrangian; the Euler-Lagrange equation is
;;;; solved for the acceleration at macroexpansion time; what is compiled is a
;;;; numeric simulation loop with no algebra in it.

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(defmacro defaccel (name (q v) lagrangian &rest params)
  "Solve d/dt(dL/dv) - dL/dq = 0 for the acceleration.

Expanding the total time derivative by the chain rule gives
  (d2L/dv2) a + (d2L/dv dq) v - dL/dq = 0,
so the acceleration is available in closed form."
  (let* ((dl/dq (maxima-diff lagrangian q))
         (dl/dv (maxima-diff lagrangian v))
         (d2l/dv2 (maxima-diff dl/dv v))
         (d2l/dvdq (maxima-diff dl/dv q))
         (accel (maxima-simplify
                  (list '/ (list '- dl/dq (list '* d2l/dvdq v)) d2l/dv2))))
    `(defun ,name (,q ,v ,@params) ,accel)))

;;; --- pendulum: L = (1/2) m l^2 v^2 + m g l cos(q) ---------------------
;;; the textbook answer is a = -(g/l) sin(q)

(defaccel pendulum-accel (q v)
  (+ (* 1/2 m (expt l 2) (expt v 2)) (* m g l (cos q)))
  m g l)

(deftest pendulum-matches-textbook 'yes
  (if (< (abs (- (pendulum-accel 0.5 0.0 2.0 9.8 1.5)
                 (* (- (/ 9.8 1.5)) (sin 0.5))))
         1e-9)
      'yes 'no))

;;; --- harmonic oscillator: L = (1/2) m v^2 - (1/2) k q^2 ---------------
;;; the answer is a = -k q / m

(defaccel spring-accel (q v)
  (- (* 1/2 m (expt v 2)) (* 1/2 k (expt q 2)))
  m k)

(deftest spring-matches-textbook 'yes
  (if (< (abs (- (spring-accel 0.3 0.0 2.0 8.0) (/ (* -8.0 0.3) 2.0))) 1e-9)
      'yes 'no))

;;; --- simulate ---------------------------------------------------------
;;; A symplectic Euler loop.  This is the part that runs, and it contains no
;;; algebra: the acceleration is arithmetic the compiler wrote down.

(defun quarter-period (q0 dt steps)
  "Integrate from rest at Q0 until the pendulum first crosses zero."
  (let ((q q0) (v 0.0) (elapsed 0.0))
    (dotimes (i steps)
      (setq v (+ v (* (pendulum-accel q v 1.0 9.8 1.0) dt)))
      (setq q (+ q (* v dt)))
      (setq elapsed (+ elapsed dt))
      (if (< q 0) (return-from quarter-period elapsed)))
    nil))

;; small oscillations have period 2*pi*sqrt(l/g) = 2.0071 s
(deftest pendulum-period 'close
  (let ((period (* 4 (quarter-period 0.05 0.0001 200000))))
    (if (< (abs (- period 2.0071)) 0.01) 'close 'off)))
