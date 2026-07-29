;;;; SBCL side of hyclb: read user source, macroexpand it, print the result.
;;;;
;;;; Protocol: we read a command keyword followed by its arguments from stdin,
;;;; write one printed form, then a sentinel line.  User source is read and
;;;; printed through a readtable whose case is :invert, so identifiers survive
;;;; the round trip exactly as the programmer spelled them.

(defpackage :hyclb (:use :cl))
(in-package :hyclb)

(defvar *protocol-out* *standard-output*
  "The protocol stream.  Anything a library prints while loading or expanding
would otherwise be interleaved with it, so it is kept separate.")

;;; --script does not read the user init file, so Quicklisp is loaded by hand.
;;; Macro-only libraries from Quicklisp -- trivia, alexandria, iterate -- are
;;; usable this way: their macros expand here and never reach the Python side.
(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
      (*standard-output* *error-output*))
  (when (probe-file setup)
    (handler-case (load setup) (error () nil))))

(defvar *user-readtable*
  (let ((rt (copy-readtable nil)))
    (setf (readtable-case rt) :invert)
    rt))

(defvar *print-readtable*
  (let ((rt (copy-readtable nil)))
    (setf (readtable-case rt) :invert)
    rt)
  "Printing is always :invert, whatever case the source is read in.  That is
what makes the name Python sees independent of the reader's case mode.")

(defvar *stop* '()
  "Operators at which macroexpansion halts -- the expansion frontier.")

(defvar *sentinel* "#<<HYCLB-END>>")

;;; ---------------------------------------------------------------- expansion

(defvar *stop-skip*
  '(("DEFUN" . 2) ("LAMBDA" . 1) ("MULTIPLE-VALUE-BIND" . 1)
    ("PY-WITH" . 1) ("PY-IMPORT" . 1) ("PY-IMPORT-AS" . 2)
    ("DEFCLASS" . 3) ("DEFMETHOD" . 2) ("DEFGENERIC" . 2) ("DEFINE-CONDITION" . 3) ("DEFUN-ASYNC" . 2) ("DEFUN-DECORATED" . 3) ("DECLAIM" . 100) ("DOTIMES" . 1) ("DOLIST" . 1) ("DO" . 1) ("DO*" . 1))
  "How many leading arguments of a frontier form are names or lambda lists
rather than expressions, and so must not be expanded.  Keyed by symbol name:
the frontier may include operators of ours, which live in another package
than the ones the bridge's own source mentions.")

(defun stop-skip (form)
  "How many leading arguments to leave alone.  DEFMETHOD is variable: the
specialised lambda list moves when a qualifier such as :before is present."
  (if (string= (symbol-name (car form)) "DEFMETHOD")
      (if (and (cddr form) (atom (third form))) 3 2)
      (or (cdr (assoc (symbol-name (car form)) *stop-skip* :test #'string=)) 0)))

(defvar *clause-forms* '("HANDLER-CASE" "RESTART-CASE")
  "Frontier forms shaped as (op protected (head (vars) body...) ...): the
protected form and every clause body are expanded, the clause heads are not.")

(defun walk-clause-form (form)
  (list* (car form)
         (expand-all (second form))
         (loop for c in (cddr form)
               collect (if (consp c)
                           (list* (first c) (second c)
                                  (mapcar #'expand-all (cddr c)))
                           c))))

(defvar *fast-stop*
  '("DOTIMES" "DOLIST" "DO" "DO*" "LOOP")
  "Iteration constructs are stopped at, rather than expanded, when a function
asks for speed: a Python for-loop is both faster and something Numba can
compile, whereas the general TAGBODY encoding is neither.")

(defun fast-stop-list ()
  (append *stop* (mapcar (lambda (n) (intern n :common-lisp-user)) *fast-stop*)))

(defun walk-stopped (form)
  "Leave a frontier form's operator alone but keep expanding inside it.

A function that asks for speed raises the frontier over the iteration
constructs for its own body, wherever that function was written -- including
inside a macro that generated it."
  (when (member (symbol-name (car form)) *clause-forms* :test #'string=)
    (return-from walk-stopped (walk-clause-form form)))
  (let ((skip (stop-skip form))
        (*stop* (if (fast-defun-p form) (fast-stop-list) *stop*)))
    (cons (car form)
          (loop for x in (cdr form)
                for i from 1
                collect (if (or (<= i skip) (atom x)) x (expand-all x))))))

(defun expand-step (form env)
  "Expand FORM one macro at a time, stopping when we reach the frontier."
  (loop
    (when (and (consp form) (symbolp (car form)) (member (car form) *stop*))
      (return (values (walk-stopped form) t)))
    (multiple-value-bind (new expanded-p) (macroexpand-1 form env)
      (unless expanded-p (return (values new nil)))
      (setf form new))))

(defun fast-defun-p (form)
  "Does this DEFUN declare (optimize (speed 3))?"
  (and (consp form) (symbolp (car form))
       (string= (symbol-name (car form)) "DEFUN")
       (loop for f in (cdddr form)
             thereis (and (consp f) (symbolp (car f))
                          (string= (symbol-name (car f)) "DECLARE")
                          (loop for spec in (cdr f)
                                thereis (and (consp spec) (symbolp (car spec))
                                             (string= (symbol-name (car spec))
                                                      "OPTIMIZE")
                                             (loop for q in (cdr spec)
                                                   thereis
                                                   (and (consp q)
                                                        (string= (symbol-name (car q))
                                                                 "SPEED")
                                                        (integerp (second q))
                                                        (>= (second q) 3)))))))))

(defun expand-all (form)
  (sb-walker:walk-form form nil
                       (lambda (f context env)
                         (declare (ignore context))
                         (expand-step f env))))

;;; ------------------------------------------------------------ gensym fixup
;;;
;;; Uninterned symbols print as #:G123, and two occurrences of that text read
;;; back as two *different* symbols -- which would silently break every
;;; expansion that binds a gensym and then refers to it.  Give each one a
;;; unique interned name before printing.

(defvar *gsym-counter* 0)

(defun rename-gensyms (form)
  (let ((seen (make-hash-table :test 'eq)))
    (labels ((walk (x)
               (cond
                 ((and (symbolp x) x (null (symbol-package x)))
                  (or (gethash x seen)
                      (setf (gethash x seen)
                            (intern (format nil "%G~d" (incf *gsym-counter*))
                                    :common-lisp-user))))
                 ((consp x) (cons (walk (car x)) (walk (cdr x))))
                 (t x))))
      (walk form))))

;;; ------------------------------------------------------------------- server

(defvar *expander-forms*
  '("DEFMACRO" "DEFMACRO!" "DEFMACRO/G!" "DEFINE-COMPILER-MACRO"
    "DEFPACKAGE" "IN-PACKAGE" "DEFINE-SYMBOL-MACRO"
    "DEFSETF" "DEFINE-SETF-EXPANDER" "DEFCONSTANT" "DEFINE-COMPILER-MACRO"
    "QUICKLOAD" "REQUIRE" "USE-PACKAGE" "LOAD-SYSTEM")
  "Forms that configure the expander rather than describe the program.
Matched by symbol name so that ql:quickload works whatever the package.")

(defun expander-form-p (form)
  (and (consp form) (symbolp (car form))
       (member (symbol-name (car form)) *expander-forms* :test #'string=)))

(defmacro quietly (&body body)
  "Run BODY with its output diverted to stderr."
  `(let ((*standard-output* *error-output*)
         (*trace-output* *error-output*))
     ,@body))

(defun defstruct-form-p (form)
  (and (consp form) (symbolp (car form))
       (string= (symbol-name (car form)) "DEFSTRUCT")))

(defun struct-setf-forms (form)
  "DEFSTRUCT is translated rather than expanded, so SBCL never learns about
its accessors.  Teach it just enough that (setf (point-x p) v) expands into a
call we also generate."
  (let* ((spec (second form))
         (name (string (if (consp spec) (car spec) spec)))
         (body (cddr form))
         (slots (loop for s in (if (stringp (car body)) (cdr body) body)
                      collect (string (if (consp s) (car s) s)))))
    (loop for s in slots
          collect `(defsetf ,(intern (concatenate 'string name "-" s)
                                     :common-lisp-user)
                       ,(intern (concatenate 'string "SET-" name "-" s)
                                :common-lisp-user)))))

;;; ---------------------------------------------------- compile-time specs
;;;
;;; The expander is a live Lisp image, so it can run the very function it is
;;; compiling.  A (spec ... :test n) declaration is therefore checked before
;;; any Python exists: a counterexample stops the build.

(define-condition spec-violation (error)
  ((text :initarg :text :reader spec-text))
  (:report (lambda (c stream) (format stream "~a" (spec-text c)))))

(defun spec-plist (form)
  "The (spec ...) entry among a DEFUN's declarations."
  (loop for f in (cdddr form)
        when (and (consp f) (symbolp (car f))
                  (string= (symbol-name (car f)) "DECLARE"))
          do (loop for e in (cdr f)
                   when (and (consp e) (symbolp (car e))
                             (string= (symbol-name (car e)) "SPEC"))
                     do (return-from spec-plist (cdr e)))))

(defun spec-get (plist key)
  "The values following :KEY, up to the next keyword."
  (let ((rest (member key plist
                      :test (lambda (k item)
                              (and (symbolp item) (string= (symbol-name item) k))))))
    (loop for item in (cdr rest)
          until (keywordp item)
          collect item)))

(defun declared-types (form)
  "Parameter name -> declared type, from (declare (type T v...))."
  (let (out)
    (loop for f in (cdddr form)
          when (and (consp f) (symbolp (car f))
                    (string= (symbol-name (car f)) "DECLARE"))
            do (loop for e in (cdr f)
                     when (and (consp e) (symbolp (car e))
                               (string= (symbol-name (car e)) "TYPE"))
                       do (loop for v in (cddr e)
                                do (push (cons v (second e)) out))))
    out))

(defun gen-value (type)
  "A random value of a declared type.  The declaration is the generator."
  (let ((name (and type (symbolp type) (symbol-name type))))
    (cond
      ((null name) (- (random 201) 100))
      ((member name '("INTEGER" "FIXNUM" "BIGNUM") :test #'string=)
       (- (random 201) 100))
      ((string= name "UNSIGNED-BYTE") (random 100))
      ((member name '("FLOAT" "DOUBLE-FLOAT" "SINGLE-FLOAT" "REAL")
               :test #'string=)
       (- (random 200.0d0) 100.0d0))
      ((member name '("STRING" "SIMPLE-STRING") :test #'string=)
       (subseq "abcdefghij" 0 (random 11)))
      ((member name '("LIST" "CONS") :test #'string=)
       (loop repeat (random 6) collect (- (random 21) 10)))
      ((string= name "SYMBOL") (nth (random 3) '(a b c)))
      ((string= name "BOOLEAN") (if (zerop (random 2)) t nil))
      (t (- (random 201) 100)))))

(defun required-params (lambda-list)
  (loop for p in lambda-list
        until (and (symbolp p) (char= (char (symbol-name p) 0) #\&))
        collect p))

(defun run-spec-tests (form)
  "Check a (spec ... :test n) declaration by running the function here."
  (let* ((plist (spec-plist form))
         (count (first (spec-get plist "TEST"))))
    (unless (and plist (integerp count) (plusp count))
      (return-from run-spec-tests nil))
    (let* ((name (second form))
           (params (required-params (third form)))
           (types (declared-types form))
           (arg-preds (spec-get plist "ARGS"))
           (ret-pred (first (spec-get plist "RET")))
           (fn-pred (first (spec-get plist "FN")))
           ;; the spec says RET; that symbol belongs to the package the user
           ;; source is read in, not to this file's
           (ret-var (intern "RET" :common-lisp-user))
           (tried 0))
      (handler-case
          (progn
            (eval form)
            (let ((argfn (coerce `(lambda ,params
                                    (declare (ignorable ,@params))
                                    (and ,@arg-preds))
                                 'function))
                  (retfn (and ret-pred
                              (coerce `(lambda (,@params ,ret-var)
                                         (declare (ignorable ,@params ,ret-var))
                                         ,ret-pred)
                                      'function)))
                  (fnfn (and fn-pred
                             (coerce `(lambda (,@params ,ret-var)
                                        (declare (ignorable ,@params ,ret-var))
                                        ,fn-pred)
                                     'function))))
              (dotimes (i count)
                (let ((args (mapcar (lambda (p) (gen-value (cdr (assoc p types))))
                                    params)))
                  (when (apply argfn args)
                    (incf tried)
                    (let ((ret (apply name args)))
                      (when (and retfn (not (apply retfn (append args (list ret)))))
                        (error 'spec-violation :text
                               (format nil ":ret violated in ~a:~{ ~a~} gave ~a"
                                       name args ret)))
                      (when (and fnfn (not (apply fnfn (append args (list ret)))))
                        (error 'spec-violation :text
                               (format nil ":fn violated in ~a:~{ ~a~} gave ~a"
                                       name args ret)))))))
              (when (zerop tried)
                (format *error-output*
                        "~&; spec: no input satisfied :args for ~a; nothing tested~%"
                        name))))
        (spec-violation (c) (error c))
        (error (e)
          ;; a function that reaches into Python cannot run here; say so
          ;; rather than pretend it was checked
          (format *error-output*
                  "~&; spec: ~a could not be tested in the expander (~a)~%"
                  name e))))))

(defun emit (form)
  (let ((*readtable* *print-readtable*)
        (*print-pretty* nil)
        (*print-circle* nil)
        (*print-readably* nil)
        (*package* (find-package :common-lisp-user))
        (*standard-output* *protocol-out*))
    (prin1 form)
    (terpri)))

(defun serve ()
  (loop
    (let ((cmd (read *standard-input* nil :quit)))
      (case cmd
        (:quit (maxima-stop) (return))
        (:set-case
         ;; :invert round-trips Python identifiers, but it also makes source
         ;; case-sensitive: an existing library that writes both C-of and
         ;; c-of for one symbol needs the standard :upcase.
         (let ((mode (read)))
           (setf (readtable-case *user-readtable*)
                 (intern (string-upcase (string mode)) :keyword))
           (emit t)))
        (:set-stop
         (let ((names (let ((*readtable* *user-readtable*)) (read))))
           ;; CL-USER inherits the standard operators and can hold ours
           (setf *stop* (mapcar (lambda (n) (intern (string n) :common-lisp-user))
                                names))
           (emit t)))
        (:expand
         (let ((form (let ((*readtable* *user-readtable*)
                           (*package* (find-package :common-lisp-user)))
                       (read))))
           (handler-case (emit (rename-gensyms (expand-all form)))
             (error (e) (emit (list :error (princ-to-string e)))))))
        (:expand-string
         ;; Expand a whole file's worth of forms.  Definitions that belong to
         ;; the expander itself -- macros, packages, proclamations -- are
         ;; evaluated here and reported as :skip rather than translated.
         (let ((text (read)))
           (handler-case
               (emit
                (let ((*readtable* *user-readtable*)
                      (*package* (find-package :common-lisp-user)))
                  (with-input-from-string (in text)
                    (loop for form = (read in nil :%eof)
                          until (eq form :%eof)
                          collect
                          (cond
                            ((expander-form-p form)
                             (quietly (eval form))
                             (list :skip))
                            ;; DECLAIM is both a fact for the expander and a
                            ;; type annotation for the generated Python
                            ((and (consp form) (symbolp (car form))
                                  (string= (symbol-name (car form)) "DECLAIM"))
                             (quietly (eval form))
                             (list :form form))
                            ((defstruct-form-p form)
                             (quietly (mapc #'eval (struct-setf-forms form)))
                             (list :form form))
                            ((and (consp form) (symbolp (car form))
                                  (string= (symbol-name (car form)) "DEFUN"))
                             (run-spec-tests form)
                             (list :form (rename-gensyms (expand-all form))))
                            (t (list :form (rename-gensyms (expand-all form)))))))))
             (error (e) (emit (list :error (princ-to-string e)))))))
        (:eval
         (let ((form (let ((*readtable* *user-readtable*)
                           (*package* (find-package :common-lisp-user)))
                       (read))))
           (handler-case (emit (rename-gensyms (eval form)))
             (error (e) (emit (list :error (princ-to-string e)))))))
        (t (emit (list :error (format nil "unknown command ~s" cmd)))))
      (write-line *sentinel* *protocol-out*)
      (force-output *protocol-out*))))


;;; ------------------------------------------------------------------ Maxima
;;;
;;; Maxima is a Common Lisp program, so it can be called as Lisp -- but it is
;;; far too large to compile through this system, and its own build here uses
;;; a different Lisp.  Instead it runs as a second subprocess of the expander
;;; and is available to macros.  A macro that differentiates its argument
;;; therefore leaves ordinary arithmetic behind, and the compiled program has
;;; no dependency on Maxima at all.

(defvar *maxima* nil)
(defvar *plain-readtable* (copy-readtable nil)
  "Maxima speaks standard Common Lisp syntax; the :invert readtable used for
user source would fold the case of everything crossing this boundary.")
(defvar *mx-begin* "#<<MX-BEGIN>>")
(defvar *mx-end* "#<<MX-END>>")

(defun maxima-start ()
  (or *maxima*
      (let ((p (sb-ext:run-program "maxima" (list "--very-quiet")
                                   :search t :input :stream :output :stream
                                   :error nil :wait nil)))
        (setf *maxima* p)
        (write-line "to_lisp();" (sb-ext:process-input p))
        ;; silence the "rat: replaced ..." notices
        (write-line "(setq $ratprint nil)" (sb-ext:process-input p))
        (force-output (sb-ext:process-input p))
        p)))

(defun strip-uninterned (text)
  "Maxima's OPTIMIZE names its temporaries with uninterned symbols.  Printed
and read back, each occurrence would be a different symbol, so the binding and
its uses would not match; interning them keeps them identical."
  (let ((out (make-string-output-stream)))
    (loop with i = 0
          while (< i (length text))
          do (if (and (< (1+ i) (length text))
                      (char= (char text i) #\#)
                      (char= (char text (1+ i)) #\:))
                 (incf i 2)
                 (progn (write-char (char text i) out) (incf i))))
    (get-output-stream-string out)))

(defun maxima-stop ()
  (when *maxima*
    ;; GCL ignores SIGTERM here, so do not ask twice
              (ignore-errors (sb-ext:process-kill *maxima* 9))
    (setf *maxima* nil)))

;; Maxima is a child of this process and does not die with it on its own;
;; without this it is left running after every compilation.
(push #'maxima-stop sb-ext:*exit-hooks*)

(defun maxima-eval (lisp-text)
  "Evaluate LISP-TEXT inside Maxima's Lisp and read back the result."
  (let* ((p (maxima-start))
         (in (sb-ext:process-input p))
         (out (sb-ext:process-output p)))
    (let ((*readtable* *plain-readtable*))
      ;; evaluate first, print second: anything Maxima says while working
      ;; then lands outside the delimited region and is skipped
      (format in "(let ((v ~a)) (princ ~s) (terpri) (prin1 v) (terpri) (princ ~s) (terpri))~%"
              lisp-text *mx-begin* *mx-end*))
    (force-output in)
    (let ((lines '()) (started nil))
      (loop
        (let ((line (read-line out nil nil)))
          (when (null line) (return))
          (cond ((search *mx-end* line) (return))
                ((search *mx-begin* line) (setf started t))
                (started (push line lines)))))
      (let ((text (strip-uninterned (format nil "~{~a~^ ~}" (nreverse lines)))))
        (let ((*package* (find-package :common-lisp-user))
              (*readtable* *plain-readtable*)
              (*read-eval* nil))
          (read-from-string text))))))

;;; Maxima keeps expressions in its own prefix form; these two functions are
;;; the whole of the impedance match.

(defun mx-op (name)
  "A Maxima operator head.  It must be interned where it will print without a
package prefix, since the text is read inside Maxima's own image."
  (list (intern name :common-lisp-user)))

(defun lisp->maxima (x)
  (cond
    ((numberp x) x)
    ((symbolp x)
     (intern (concatenate 'string "$" (string x)) :common-lisp-user))
    ((consp x)
     (let ((op (string (car x)))
           (args (mapcar #'lisp->maxima (cdr x))))
       (cond
         ;; (aref a n) is Maxima's a[n]
         ((string= op "AREF")
          (cons (list (intern (concatenate 'string "$" (string (second x)))
                              :common-lisp-user)
                      (intern "ARRAY" :common-lisp-user))
                (mapcar #'lisp->maxima (cddr x))))
         ((string= op "=") (cons (mx-op "MEQUAL") args))
         ((string= op "<") (cons (mx-op "MLESSP") args))
         ((string= op ">") (cons (mx-op "MGREATERP") args))
         ((string= op "+") (cons (mx-op "MPLUS") args))
         ((string= op "*") (cons (mx-op "MTIMES") args))
         ;; Maxima's canonical division is multiplication by a power; the
         ;; MQUOTIENT verb form is left unsimplified and DIFF stalls on it
         ((string= op "/")
          (if (= (length args) 1)
              (list (mx-op "MEXPT") (first args) -1)
              (cons (mx-op "MTIMES")
                    (cons (first args)
                          (mapcar (lambda (a) (list (mx-op "MEXPT") a -1))
                                  (rest args))))))
         ((string= op "EXPT") (cons (mx-op "MEXPT") args))
         ((string= op "-")
          (if (= (length args) 1)
              (list (mx-op "MTIMES") -1 (first args))
              (list* (mx-op "MPLUS") (first args)
                     (mapcar (lambda (a) (list (mx-op "MTIMES") -1 a))
                             (rest args)))))
         ;; Maxima has no %exp: the exponential is a power of %e
         ((string= op "EXP")
          (list (mx-op "MEXPT") (intern "$%E" :common-lisp-user) (first args)))
         ((member op '("SIN" "COS" "TAN" "LOG" "SQRT") :test #'string=)
          (list (list (intern (concatenate 'string "%" op) :common-lisp-user))
                (first args)))
         (t (error "cannot express in Maxima: ~s" x)))))
    (t (error "cannot express in Maxima: ~s" x))))

(defun maxima->lisp (x)
  (cond
    ((numberp x) x)
    ((symbolp x)
     (let ((n (string x)))
       (cond
       ((string= n "$%E") 'exp-base-e)
       ((string= n "$%PI") 'pi)
       (t (intern (if (and (plusp (length n)) (char= (char n 0) #\$))
                      (subseq n 1)
                      n)
                  :common-lisp-user)))))
    ((and (consp x) (string= (string (if (consp (car x)) (caar x) (car x)))
                             "MPROG"))
     ;; OPTIMIZE returns a block of temporaries: exactly a LET*.  It is
     ;; handled before the arguments are converted, because its parts are
     ;; assignments rather than expressions.
     (let* ((body (rest (cdr x)))
            (steps (butlast body))
            (result (car (last body))))
       (list 'let*
             (mapcar (lambda (step)
                       (list (maxima->lisp (second step))
                             (maxima->lisp (third step))))
                     steps)
             (maxima->lisp result))))
    ;; a[n] comes back as (($A SIMP ARRAY) $N)
    ((and (consp x) (consp (car x))
          (member "ARRAY" (mapcar #'string (cdar x)) :test #'string=))
     (list* 'aref (maxima->lisp (caar x)) (mapcar #'maxima->lisp (cdr x))))
    ((consp x)
     (let* ((head (string (if (consp (car x)) (caar x) (car x))))
            (args (mapcar #'maxima->lisp (cdr x))))
       (cond
         ((string= head "MLIST") (cons 'list args))
         ((string= head "MEQUAL") (cons '= args))
         ((string= head "MPLUS") (cons '+ args))
         ((string= head "MTIMES") (cons '* args))
         ((string= head "MEXPT")
          (if (and (symbolp (first (cdr x)))
                   (string= (string (first (cdr x))) "$%E"))
              (cons 'exp (cdr args))
              (cons 'expt args)))
         ((string= head "MQUOTIENT") (cons '/ args))
         ((string= head "RAT") (cons '/ args))
         ((string= head "MMINUS") (cons '- args))
         ((string= head "%SIN") (cons 'sin args))
         ((string= head "%COS") (cons 'cos args))
         ((string= head "%TAN") (cons 'tan args))
         ((string= head "%EXP") (cons 'exp args))
         ((string= head "%LOG") (cons 'log args))
         ((string= head "%SQRT") (cons 'sqrt args))
         (t (error "cannot express in Lisp: ~s" x)))))
    (t x)))

(defun maxima-apply (fn &rest args)
  "Call a Maxima function on Lisp expressions and get a Lisp expression back."
  (maxima->lisp
   (maxima-eval
    (let ((*package* (find-package :common-lisp-user))
          (*readtable* *plain-readtable*))
      (format nil "(mfuncall '~a~{ '~s~})" fn (mapcar #'lisp->maxima args))))))

(defun maxima-diff (expr var) (maxima-apply "$diff" expr var))

(defvar *solve-rec-loaded* nil)

(defun maxima-solve-rec (equation term &optional initial)
  "Solve a recurrence symbolically and return the closed form of the term.

The equation is written with AREF, so (aref a (+ n 1)) is Maxima's a[n+1]."
  (unless *solve-rec-loaded*
    (maxima-eval "(mfuncall '$load '$solve_rec)")
    (setf *solve-rec-loaded* t))
  (let ((solution
          (maxima->lisp
           (maxima-eval
            (let ((*package* (find-package :common-lisp-user))
                  (*readtable* *plain-readtable*))
              (format nil "(mfuncall '$solve_rec '~s '~s~@[ '~s~])"
                      (lisp->maxima equation)
                      (lisp->maxima term)
                      (and initial (lisp->maxima initial))))))))
    ;; the answer is (= (aref a n) closed-form)
    (if (and (consp solution) (eq (car solution) (intern "=" :common-lisp-user)))
        (third solution)
        solution)))

(defun maxima-taylor (expr var point order)
  "The Taylor polynomial, as ordinary arithmetic."
  (maxima->lisp
   (maxima-eval
    (let ((*package* (find-package :common-lisp-user))
          (*readtable* *plain-readtable*))
      (format nil "(mfuncall '$ratdisrep (mfuncall '$taylor '~s '~s ~s ~s))"
              (lisp->maxima expr) (lisp->maxima var) point order)))))

(defun maxima-optimize (expr)
  "Common subexpression elimination, performed by Maxima."
  (maxima-apply "$optimize" expr))

(defun maxima-horner (expr var) (maxima-apply "$horner" expr var))

(defun maxima-solve (equation var)
  "Solve for VAR and return the first root as an expression."
  (let ((roots (maxima-apply "$solve" equation var)))
    ;; ((mlist) ((mequal) $x expr) ...) becomes (list (= x expr) ...)
    (if (and (consp roots) (eq (car roots) 'list) (consp (second roots)))
        (third (second roots))
        roots)))

(defun maxima-provable-p (a b)
  "Is A = B an identity?  Checked while the program is compiled."
  (eq (maxima-eval
       (let ((*package* (find-package :common-lisp-user))
             (*readtable* *plain-readtable*))
         (format nil "(mfuncall '$is (mfuncall '$equal '~s '~s))"
                 (lisp->maxima a) (lisp->maxima b))))
      (intern "T" :common-lisp-user)))
(defun maxima-integrate (expr var) (maxima-apply "$integrate" expr var))
(defun maxima-simplify (expr) (maxima-apply "$ratsimp" expr))
(defun maxima-expand (expr) (maxima-apply "$expand" expr))
(defun maxima-factor (expr) (maxima-apply "$factor" expr))

(import '(maxima-diff maxima-integrate maxima-simplify maxima-expand
          maxima-factor maxima-apply lisp->maxima maxima->lisp
          maxima-taylor maxima-optimize maxima-horner maxima-solve
          maxima-provable-p maxima-solve-rec)
        :common-lisp-user)

(serve)
