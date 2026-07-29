(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

(defclass shape () ((name :initform "shape" :accessor shape-name)))
(defclass circle (shape) ((r :initform 1 :accessor circle-r)))
(defclass square (shape) ((side :initform 1 :accessor square-side)))

(defmethod area ((s circle)) (* 3.14159 (circle-r s) (circle-r s)))
(defmethod area ((s square)) (* (square-side s) (square-side s)))

;; single dispatch on the subclass
(deftest clos-dispatch-circle 12.56636 (area (make-instance 'circle :r 2)))
(deftest clos-dispatch-square 9        (area (make-instance 'square :side 3)))

;; accessors and slot writing
(deftest clos-accessor 5 (circle-r (make-instance 'circle :r 5)))
(deftest clos-default 1  (circle-r (make-instance 'circle)))
(deftest clos-inherit "shape" (shape-name (make-instance 'circle)))

;; multiple dispatch -- the thing Python cannot do
(defmethod collide ((a circle) (b circle)) 'circle-circle)
(defmethod collide ((a circle) (b square)) 'circle-square)
(defmethod collide ((a shape)  (b shape))  'generic)

(deftest multi-cc 'circle-circle (collide (make-instance 'circle) (make-instance 'circle)))
(deftest multi-cs 'circle-square (collide (make-instance 'circle) (make-instance 'square)))
(deftest multi-fallback 'generic (collide (make-instance 'square) (make-instance 'square)))

;; before/after qualifiers
(defparameter *log* nil)
(defmethod greet ((s shape)) 'hello)
(defmethod greet :before ((s shape)) (setq *log* (cons 'before *log*)))
(defmethod greet :after ((s shape)) (setq *log* (cons 'after *log*)))
(deftest qualifiers 'hello (greet (make-instance 'shape)))
(deftest qualifier-order '(after before) *log*)
