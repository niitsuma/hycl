;;;; A hyperparameter sweep whose grid is computed while the program is being
;;;; compiled, not while it runs.
;;;;
;;;; The point is not that a grid is hard to build at run time -- it is that
;;;; the macro can inspect it and emit different code per configuration.

(py-import torch)
(py-import torch.utils.data)
(py-import lightning)

(defmacro deftest (name expected form)
  `(let ((got ,form))
     (if (equal got ,expected) (print (list 'pass ',name))
         (print (list 'FAIL ',name 'got got)))))

;;; --- the sweep macro -------------------------------------------------

(defmacro defsweep (name &rest axes)
  "(defsweep g (:lr 0.1 0.01) (:width 4 8)) binds G to the cartesian product."
  (labels ((product (axes)
             (if (null axes)
                 (list nil)
                 (let ((key (caar axes))
                       (vals (cdar axes))
                       (rest (product (cdr axes))))
                   (loop for v in vals
                         append (loop for r in rest
                                      collect (list* key v r)))))))
    `(defparameter ,name ',(product axes))))

(defsweep grid (:lr 0.1 0.01) (:width 2 4))

(deftest sweep-size 4 (length grid))
(deftest sweep-first '(:lr 0.1 :width 2) (first grid))

;;; --- one model per configuration -------------------------------------

(defun build (config)
  (let ((width (getf config :width)))
    (py-call torch.nn.Sequential
             (torch.nn.Linear 1 width)
             (torch.nn.ReLU)
             (torch.nn.Linear width 1))))

(defun param-count (net)
  (let ((n 0))
    (dolist (p (py-list (py-method net "parameters")) n)
      (setq n (+ n (py-method p "numel"))))))

(deftest sweep-builds '(7 13)
  (list (param-count (build (first grid)))    ; width 2
        (param-count (build (second grid))))) ; width 4

;;; --- train the smallest configuration ---------------------------------

(defmacro deflit (name layers &key (lr 0.1))
  `(setq ,name
     (py-class ,(string name)
               (list lightning.LightningModule)
               "__init__"
               (lambda (self)
                 (py-call (py-attr lightning.LightningModule "__init__") self)
                 (py-set-attr self "net" ,layers))
               "forward"
               (lambda (self x) (py-call (py-attr self "net") x))
               "training_step"
               (lambda (self batch idx)
                 (py-call torch.nn.functional.mse_loss
                          (py-call (py-attr self "net") (py-getitem batch 0))
                          (py-getitem batch 1)))
               "configure_optimizers"
               (lambda (self)
                 (py-call torch.optim.SGD (py-method self "parameters") :lr ,lr)))))

(deflit swept-net (torch.nn.Linear 1 1) :lr 0.1)

(defun loader ()
  (let* ((xs (torch.randn 128 1))
         (ys (py-call torch.mul xs 3.0)))
    (py-call torch.utils.data.DataLoader
             (torch.utils.data.TensorDataset xs ys) :batch_size 16)))

(defun quiet-trainer (epochs)
  (py-call lightning.Trainer :max_epochs epochs :accelerator "cpu"
           :logger py-false :enable_progress_bar py-false
           :enable_checkpointing py-false :enable_model_summary py-false))

(setq model (py-call swept-net))
(py-method (quiet-trainer 30) "fit" model (loader))

(setq weight (py-method (py-getitem (py-list (py-method model "parameters")) 0) "item"))
(deftest sweep-trains 'yes (if (< (abs (- weight 3.0)) 0.5) 'yes 'no))
