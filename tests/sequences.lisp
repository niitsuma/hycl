;;;; Symbolic sequences, lazy streams, and machine code -- in one pipeline.
;;;;
;;;; A recurrence is written down.  Maxima solves it symbolically while the
;;;; program is compiled.  The closed form becomes two things: a lazy stream,
;;;; for looking at terms one at a time, and a numeric kernel that Numba turns
;;;; into machine code, for consuming a great many of them.
;;;;
;;;; The three layers are not glued together at run time.  They are all
;;;; produced by one macro from one recurrence.

(py-import numpy)

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(defmacro defseq (name index element-type equation initial)
  "Solve a recurrence and compile the sequence it describes.

Defines <name>-term, the closed form as a Numba kernel; <name>-from, a lazy
stream of the terms; and <name>-sum, a compiled loop over them.  The element
type must be declared: under (safety 0) the arithmetic is the machine's, and
2^-n is zero in integers where Common Lisp would answer 1/2^n."
  (labels ((floatify (x)
             ;; a negative exponent is a rational in Common Lisp and zero in
             ;; integer arithmetic, so a float sequence floats its bases
             (cond ((and (consp x) (eq (car x) 'expt))
                    (list 'expt (list 'float (floatify (second x)))
                          (floatify (third x))))
                   ((consp x) (mapcar #'floatify x))
                   (t x))))
   (let* ((closed (maxima-solve-rec equation (list 'aref 'a index) initial))
          (body (if (member element-type '(double-float single-float float))
                    (floatify closed)
                    closed))
          (term   (intern (concatenate 'string (string name) "-TERM")))
          (from   (intern (concatenate 'string (string name) "-FROM")))
          (total  (intern (concatenate 'string (string name) "-SUM"))))
    `(progn
       ;; the numeric kernel: no Lisp values, so Numba can compile it
       (defun ,term (,index)
         (declare (type integer ,index) (type ,element-type ,term)
                  (optimize (speed 3) (safety 0)))
         ,body)
       ;; the lazy stream: ordinary compiled code, forced on demand
       (defun ,from (,index)
         (cons-stream (,term ,index) (,from (+ ,index 1))))
       ;; forcing many terms at once stays inside the fast path
       (defun ,total (n)
         (declare (type integer n) (optimize (speed 3) (safety 0)))
         (let ((acc 0.0))
           (dotimes (i n) (setq acc (+ acc (,term i))))
           acc))))))

;;; --- a[n+1] = 2 a[n] + 1, a[0] = 0.  Maxima answers 2^n - 1. ----------

(defseq mersenne n integer
  (= (aref a (+ n 1)) (+ (* 2 (aref a n)) 1))
  (= (aref a 0) 0))

(deftest closed-form-0 0 (mersenne-term 0))
(deftest closed-form-10 1023 (mersenne-term 10))

;; the lazy stream: terms appear one at a time, on demand
(deftest stream-take '(0 1 3 7 15) (stream-take 5 (mersenne-from 0)))
(deftest stream-nth 4095 (stream-nth 12 (mersenne-from 0)))

;; and the same sequence consumed in bulk, as machine code
(deftest bulk-sum 1013.0 (mersenne-sum 10))

;;; --- a[n+1] = a[n]/2, a[0] = 1: a convergent series ------------------
;;; Written in floating point on purpose.  Under (safety 0) the arithmetic is
;;; the machine's, not Common Lisp's: 2^-n is zero in integers, not 1/2^n.

(defseq halving n double-float
  (= (aref a (+ n 1)) (* 0.5 (aref a n)))
  (= (aref a 0) 1.0))

(deftest halving-stream '(1.0 0.5 0.25 0.125) (stream-take 4 (halving-from 0)))
(deftest halving-converges 'yes
  (if (< (abs (- (halving-sum 60) 2.0)) 1e-9) 'yes 'no))
