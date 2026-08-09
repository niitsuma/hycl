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

(defvar *binding-forms* '("HANDLER-BIND")
  "Frontier forms shaped as (op ((name form) ...) body...): the bound forms
and the body are expanded, the names are not.")

(defun walk-binding-form (form)
  (list* (car form)
         (loop for b in (second form)
               collect (list* (first b) (mapcar #'expand-all (rest b))))
         (mapcar #'expand-all (cddr form))))

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
  (when (member (symbol-name (car form)) *binding-forms* :test #'string=)
    (return-from walk-stopped (walk-binding-form form)))
  (let ((skip (stop-skip form))
        (*stop* (if (fast-defun-p form) (fast-stop-list) *stop*)))
    (cons (car form)
          (loop for x in (cdr form)
                for i from 1
                collect (if (or (<= i skip) (atom x)) x (expand-all x))))))

(defun form-start (stream)
  "The character offset where the next form begins.

Whitespace and comment lines are stepped over first, so the offset names the
form rather than whatever blank space preceded it.  The back end turns it into
a line number, which is what a traceback shows."
  (loop
    (let ((c (peek-char t stream nil :%eof)))
      (cond ((eq c :%eof) (return (file-position stream)))
            ((char= c #\;) (read-line stream nil))
            (t (return (file-position stream)))))))

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
;;;
;;; The same walk undoes the occasional internal function that slips through
;;; a standard macro's expansion.  SBCL 2.5 grew one: LOOP's collect starts
;;; its accumulator with SB-KERNEL::UNALIGNED-DX-CONS, which is (cons ITEM
;;; nil) plus an allocation hint no other Lisp -- and no Python -- has.

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
                 ((and (consp x) (symbolp (car x)) (car x)
                       (string= (symbol-name (car x)) "UNALIGNED-DX-CONS"))
                  (list 'cons (walk (second x)) nil))
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
                    (loop for offset = (form-start in)
                          for form = (read in nil :%eof)
                          until (eq form :%eof)
                          collect
                          (cond
                            ((expander-form-p form)
                             (quietly (eval form))
                             (list :skip offset))
                            ;; DECLAIM is both a fact for the expander and a
                            ;; type annotation for the generated Python
                            ((and (consp form) (symbolp (car form))
                                  (string= (symbol-name (car form)) "DECLAIM"))
                             (quietly (eval form))
                             (list :form form offset))
                            ((defstruct-form-p form)
                             (quietly (mapc #'eval (struct-setf-forms form)))
                             (list :form form offset))
                            ((and (consp form) (symbolp (car form))
                                  (string= (symbol-name (car form)) "DEFUN"))
                             (run-spec-tests form)
                             (let ((derived (derive-type form)))
                               (if derived
                                   (list :form (rename-gensyms (expand-all form))
                                         offset derived)
                                   (list :form (rename-gensyms (expand-all form))
                                         offset))))
                            (t (list :form (rename-gensyms (expand-all form)) offset)))))))
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
          (strip-maxima-src (values (read-from-string text))))))))

(defun maxima-src-note-p (x)
  (and (consp x) (integerp (car x))
       (find-if (lambda (e) (and (symbolp e) (string= (symbol-name e) "SRC")))
                (cdr x))))

(defun strip-maxima-src (x)
  "Maxima built with source tracking -- 5.47 here -- hangs (LINE \"file\" SRC
FN POS) notes in operator flag lists, and (string ...) on one of those is a
type error in every reader of Maxima forms below.  They mean nothing on this
side; drop them wherever they appear."
  (if (consp x)
      (mapcar #'strip-maxima-src (remove-if #'maxima-src-note-p x))
      x))

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

;;; ------------------------------------------------------------------
;;; DEFLLM: a language model in Maxima's seat.
;;;
;;; The expander may consult any process it likes, and a local model is one
;;; more: prompted while the program compiles, gone by the time it runs.  The
;;; difference from Maxima is trust.  Algebra Maxima returns is accepted as
;;; such; an answer sampled from a model never is.  DEFLLM therefore refuses
;;; to expand without :CHECK clauses, evaluates the model's expression
;;; against them here in SBCL, and feeds each failure back for another
;;; attempt.  What survives is an ordinary DEFUN, translated like anything
;;; else -- the compiled program depends on the model exactly as much as it
;;; depends on Maxima, which is not at all.  And since compiled .lisp modules
;;; are cached as bytecode, the model is consulted when the source changes,
;;; not on every run.
;;;
;;; The checks run in this image, so they establish the expression is right
;;; in Common Lisp terms; whether its translation is right in Python is the
;;; test suite's business, the same as for handwritten code.

(defvar *llm-program* (or (sb-ext:posix-getenv "HYCLB_LLM") "ask-local")
  "A command that takes a prompt and prints one completion, called as
PROGRAM --model M --max-tokens N [--system S] PROMPT.  Whatever
authentication it needs is its own affair; nothing secret appears here or in
the source being compiled.  HYCLB_LLM overrides the default.")

(defvar *llm-model* (or (sb-ext:posix-getenv "HYCLB_LLM_MODEL") "qwen3.6"))

(defun llm-ask (prompt &key system (max-tokens 400))
  "One completion from the local model, as a string."
  (let* ((out (make-string-output-stream))
         (p (ignore-errors
              (sb-ext:run-program
               *llm-program*
               (append (list "--model" *llm-model*
                             "--max-tokens" (princ-to-string max-tokens))
                       (when system (list "--system" system))
                       (list prompt))
               :search t :output out :error nil :wait t))))
    (unless (and p (eql 0 (sb-ext:process-exit-code p)))
      (error "~a did not answer; nothing that expands through the model ~
              can compile without it" *llm-program*))
    (get-output-stream-string out)))

(defun llm-first-form (text)
  "The first complete s-expression in TEXT.  Whatever surrounds it -- prose,
markdown fences -- is skipped rather than forbidden: a prompt can ask for the
bare expression, but only reading can enforce it."
  (let ((*package* (find-package :common-lisp-user))
        (*readtable* *plain-readtable*)
        (*read-eval* nil))
    (loop for i = (position #\( text) then (position #\( text :start (1+ i))
          while i
          do (handler-case (return (values (read-from-string text t nil :start i)))
               (error () nil)))))

(defun llm-close-enough (got want tolerance)
  (cond ((and (numberp got) (numberp want))
         (if tolerance
             (< (abs (- got want)) tolerance)
             (or (eql got want)
                 (< (abs (- got want)) (* 1d-9 (max 1 (abs got) (abs want)))))))
        ;; EQUALP would fold string case, and accept "iv" for "IV"
        ((and (stringp got) (stringp want)) (string= got want))
        (t (equalp got want))))

(defun llm-run-checks (params body checks tolerance)
  "NIL if BODY passes every check, else one sentence saying how it failed,
phrased for the model to read."
  (let ((fn (handler-case
                (handler-bind ((warning #'muffle-warning))
                  (eval `(lambda ,params ,body)))
              (error (e) (return-from llm-run-checks
                           (format nil "did not compile: ~a" e))))))
    (dolist (c checks nil)
      (destructuring-bind (args want) c
        (let ((got (handler-case (apply fn args)
                     (error (e)
                       (return-from llm-run-checks
                         (format nil "signalled \"~a\" with ~{~a = ~s~^, ~}"
                                 e (mapcan #'list (copy-list params)
                                           (copy-list args))))))))
          (unless (llm-close-enough got want tolerance)
            (return-from llm-run-checks
              (format nil "evaluated to ~s with ~{~a = ~s~^, ~} where ~s ~
                           is required"
                      got (mapcan #'list (copy-list params) (copy-list args))
                      want))))))))

(defun llm-defun-body (name params description checks tolerance)
  "A body expression for NAME that passes every check, or an error.
Formatting and reading both happen under the standard readtable in CL-USER:
the model speaks plain Common Lisp, not the :invert dialect of the source."
  (let ((*package* (find-package :common-lisp-user))
        (*readtable* *plain-readtable*))
    (let ((system "You write Common Lisp.  Reply with exactly one Common ~
Lisp expression and nothing else: no markdown, no comments, no DEFUN ~
wrapper.  Use only standard Common Lisp operators and functions.")
          (task (format nil "Write the body of a Common Lisp function ~a ~
with parameters ~a.  It computes: ~a.~{  With ~a the value must be ~s.~}~
~@[  Each value must match within ~a.~]"
                        name params description
                        (mapcan (lambda (c)
                                  (list (format nil "~{~a = ~s~^, ~}"
                                                (mapcan #'list
                                                        (copy-list params)
                                                        (copy-list (first c))))
                                        (second c)))
                                checks)
                        tolerance))
          (verdict "was never asked"))
      (dotimes (attempt 3)
        (let* ((reply (llm-ask task :system (format nil system)))
               (body (llm-first-form reply)))
          (setf verdict (if body
                            (llm-run-checks params body checks tolerance)
                            "contained no readable Lisp expression"))
          (when (null verdict)
            (return-from llm-defun-body body))
          (setf task (format nil "~a~%Your previous reply~@[ ~s~] ~a.  ~
Reply with one corrected expression only." task body verdict))))
      (error "defllm ~a: three answers from ~a all failed; the last ~a"
             name *llm-model* verdict))))

(defmacro cl-user::defllm (name params description &rest checks)
  "Define NAME from an English DESCRIPTION; the body is written by the local
model while the program compiles.

Each check is (:check (args...) value), all literal data.  Checks are
mandatory -- an answer nothing constrains is prose, not code -- and they are
shown to the model, so one set of literals serves as examples and acceptance
test at once.  A body that fails is sent back with the failing case up to
twice; a third failure is a compile-time error, the same treatment DEFSUM
gives a sum that does not telescope.

A (:tolerance EPS) clause loosens every numeric comparison to within EPS of
the check value, which turns the checks into sampled data: give the model
measured points and ask it for the function underneath."
  (let ((tolerance nil) (cases '()))
    (dolist (c checks)
      (cond ((and (consp c) (eq (car c) :tolerance)
                  (= (length c) 2) (realp (second c)))
             (setf tolerance (second c)))
            ((and (consp c) (eq (car c) :check)
                  (= (length c) 3) (listp (second c)))
             (push (cdr c) cases))
            (t (error "defllm ~a: malformed clause ~s; expected ~
                       (:check (args...) value) or (:tolerance eps)"
                      name c))))
    (unless cases
      (error "defllm ~a: no :check clauses.  An unchecked answer from a ~
              model is not code; state what the function must return on at ~
              least one input." name))
    `(defun ,name ,params
       ,(llm-defun-body name params description (nreverse cases) tolerance))))

;;; ------------------------------------------------------------------
;;; DEFSUM: summed-area tables derived from the sum itself.
;;;
;;; The source form is the specification -- a nested sum over axis-aligned
;;; boxes from the origin.  The recurrence that makes it O(n^N) to build and
;;; O(2^N) to query is not pattern-matched out of a loop; it is DERIVED, by
;;; telescoping the sum symbolically: split off each axis's last term and let
;;; Maxima cancel the rest.  A summand for which that reduction fails -- one
;;; that mentions an outer bound, as a convolution does -- is rejected at
;;; expansion time instead of being compiled wrongly.
;;;
;;; The derived code is then checked against the naive sum, in this image, on
;;; random data, before any Python exists.  The algebra says the recurrence is
;;; right; the self-check says the generated code implements it.

(defun mx-var (sym)
  (intern (concatenate 'string "$" (string sym)) :common-lisp-user))

(defun mx-raw (fmt &rest args)
  "A Maxima call on already-converted expression trees."
  (maxima-eval
   (let ((*package* (find-package :common-lisp-user))
         (*readtable* *plain-readtable*))
     (apply #'format nil fmt args))))

(defun mx-sum-p (e idx)
  (and (consp e) (consp (car e)) (symbolp (caar e))
       (string= (symbol-name (caar e)) "%SUM")
       (eq (third e) idx)))

(defun mx-split (e idx)
  "Split off the last term of every sum over IDX: sum(f,k,0,h) becomes
sum(f,k,0,h-1) + f[k:=h].  Structural, so it needs no simplifier."
  (cond ((mx-sum-p e idx)
         (destructuring-bind (head f i lo hi) e
           (declare (ignore head))
           (list (mx-op "MPLUS")
                 (list (mx-op "%SUM") f i lo (list (mx-op "MPLUS") hi -1))
                 (subst hi i f))))
        ((consp e) (cons (mx-split (car e) idx) (mx-split (cdr e) idx)))
        (t e)))

(defun defsum-telescopes-p (axes summand)
  "Does the inclusion-exclusion difference of the sum reduce to the summand?

AXES is ((run bound dim) ...).  The difference is taken one axis at a time:
split the sums over this axis's index, subtract the expression with the bound
lowered by one, and have Maxima expand; after the last axis nothing but the
summand at the boundary point may remain."
  (let ((e (lisp->maxima summand)))
    (dolist (ax (reverse axes))
      (setf e (list (mx-op "%SUM") e (mx-var (first ax)) 0 (mx-var (second ax)))))
    (dolist (ax axes)
      (let* ((idx (mx-var (first ax)))
             (bound (mx-var (second ax)))
             (lowered (subst (list (mx-op "MPLUS") bound -1) bound e)))
        (setf e (mx-raw "(mfuncall '$expand '~s)"
                        (list (mx-op "MPLUS")
                              (mx-split e idx)
                              (list (mx-op "MTIMES") -1 lowered))))))
    (let ((boundary (lisp->maxima summand)))
      (dolist (ax axes)
        (setf boundary (subst (mx-var (second ax)) (mx-var (first ax)) boundary)))
      (eq (mx-raw "(mfuncall '$is (mfuncall '$equal '~s '~s))" e boundary)
          (intern "T" :common-lisp-user)))))

;;; code generation --------------------------------------------------------

(defun subsets (list)
  (if (null list)
      (list nil)
      (let ((rest (subsets (cdr list))))
        (append rest (mapcar (lambda (s) (cons (car list) s)) rest)))))

(defun flat-index (points dims)
  "Row-major index into flat storage: ((p1*d2 + p2)*d3 + p3) ..."
  (let ((acc (first points)))
    (loop for p in (rest points)
          for d in (rest dims)
          do (setf acc `(+ (* ,acc ,d) ,p)))
    acc))

(defun summand-free (summand run-vars)
  "The summand's free variables, in order of first occurrence, and the arity
each is used with under AREF (NIL for a scalar)."
  (let ((seen '()) (arity '()))
    (labels ((walk (x)
               (cond ((symbolp x)
                      (unless (or (member x run-vars) (assoc x seen))
                        (push (cons x nil) seen)))
                     ((consp x)
                      (if (and (symbolp (car x))
                               (string= (symbol-name (car x)) "AREF"))
                          (progn
                            (unless (assoc (second x) seen)
                              (push (cons (second x) t) seen))
                            (setf arity
                                  (acons (second x) (length (cddr x)) arity))
                            (mapc #'walk (cddr x)))
                          (mapc #'walk (cdr x)))))))
      (walk summand)
      (values (mapcar #'car (reverse seen))
              (lambda (v) (cdr (assoc v arity)))))))

(defun defsum-names (name suffix)
  (intern (concatenate 'string (symbol-name name) suffix)
          (symbol-package name)))

(defun gen-defsum (name axes summand element-type)
  "The build, query and naive definitions, as forms to translate."
  (let* ((runs (mapcar #'first axes))
         (bounds (mapcar #'second axes))
         (dims (mapcar #'third axes))
         (float-p (member (string element-type)
                          '("DOUBLE-FLOAT" "SINGLE-FLOAT" "FLOAT")
                          :test #'string=))
         (zero (if float-p 0.0 0))
         (params (summand-free summand runs))
         (s (intern "%S" (symbol-package name)))
         (at-point (sublis (mapcar #'cons runs bounds) summand))
         (los (mapcar (lambda (b) (defsum-names b "-LO")) bounds))
         (his (mapcar (lambda (b) (defsum-names b "-HI")) bounds)))
    (labels ((guarded (sub form)
               (let ((tests (mapcar (lambda (b) `(> ,b 0))
                                    (mapcar #'second sub))))
                 (cond ((null tests) form)
                       ((null (rest tests)) `(when ,(first tests) ,form))
                       (t `(when (and ,@tests) ,form))))))
      (values
       ;; build: S over the whole array, by the derived recurrence
       `(defun ,(defsum-names name "-BUILD") (,@params ,s ,@dims)
          (declare (type integer ,@dims) (optimize (speed 3) (safety 0)))
          ,(let ((inner
                   `(progn
                      (let ((acc ,at-point))
                        ,@(loop for sub in (remove nil (subsets axes))
                                collect
                                (guarded sub
                                  `(setq acc
                                     (,(if (oddp (length sub)) '+ '-)
                                      acc
                                      (aref ,s
                                            ,(flat-index
                                              (mapcar (lambda (ax)
                                                        (if (member ax sub)
                                                            `(- ,(second ax) 1)
                                                            (second ax)))
                                                      axes)
                                              dims))))))
                        (setf (aref ,s ,(flat-index bounds dims)) acc)))))
             (dolist (ax (reverse axes) inner)
               (setf inner `(dotimes (,(second ax) ,(third ax)) ,inner))))
          ,s)
       ;; query: any box [lo,hi] per axis, by inclusion-exclusion
       `(defun ,(defsum-names name "-QUERY") (,s ,@dims ,@(mapcan #'list los his))
          (declare (type integer ,@dims ,@los ,@his)
                   (optimize (speed 3) (safety 0)))
          (let ((acc ,zero))
            ,@(loop for sub in (subsets axes)
                    collect
                    (let ((tests (mapcar
                                  (lambda (ax)
                                    `(> ,(nth (position ax axes) los) 0))
                                  sub))
                          (term `(setq acc
                                   (,(if (oddp (length sub)) '- '+)
                                    acc
                                    (aref ,s
                                          ,(flat-index
                                            (mapcar (lambda (ax)
                                                      (let ((i (position ax axes)))
                                                        (if (member ax sub)
                                                            `(- ,(nth i los) 1)
                                                            (nth i his))))
                                                    axes)
                                            dims))))))
                      (cond ((null tests) term)
                            ((null (rest tests)) `(when ,(first tests) ,term))
                            (t `(when (and ,@tests) ,term)))))
            acc))
       ;; naive: the sum as written, for the oracle and for honesty
       `(defun ,(defsum-names name "-NAIVE") (,@params ,@(mapcan #'list los his))
          (declare (type integer ,@los ,@his) (optimize (speed 3) (safety 0)))
          (let ((acc ,zero))
            ,(let ((inner `(setq acc (+ acc ,summand))))
               (loop for ax in (reverse axes)
                     for i = (position ax axes)
                     for cnt = (intern (concatenate 'string "%C"
                                                    (symbol-name (first ax)))
                                       (symbol-package name))
                     do (setf inner
                              `(dotimes (,cnt (+ (- ,(nth i his) ,(nth i los)) 1))
                                 (let ((,(first ax) (+ ,(nth i los) ,cnt)))
                                   ,inner))))
               inner)
            acc))))))

(defun defsum-selfcheck (name build query naive axes summand element-type)
  "Run the derived code against the naive sum, here in SBCL, on random data."
  (eval build) (eval query) (eval naive)
  (let* ((runs (mapcar #'first axes))
         (rank (length axes))
         (dims (subseq '(7 6 5) 0 rank))
         (float-p (member (string element-type)
                          '("DOUBLE-FLOAT" "SINGLE-FLOAT" "FLOAT")
                          :test #'string=))
         (seed 987654321))
    (flet ((rnd (m) (setf seed (mod (+ (* seed 1103515245) 12345) 2147483648))
                    (mod seed m)))
      (multiple-value-bind (params arity-of) (summand-free summand runs)
        (let* ((values
                 (mapcar (lambda (v)
                           (let ((k (funcall arity-of v)))
                             (if k
                                 (let* ((side (+ (reduce #'max dims) 2))
                                        (total (expt side k))
                                        (a (make-array total)))
                                   (dotimes (i total)
                                     (setf (aref a i)
                                           (let ((r (- (rnd 19) 9)))
                                             (if float-p (float r) r))))
                                   ;; the summand indexes it as rank-K, so
                                   ;; give it that shape
                                   (if (> k 1)
                                       (make-array (make-list k :initial-element side)
                                                   :displaced-to a)
                                       a))
                                 3)))
                         params))
               (s (make-array (reduce #'* dims)
                              :initial-element (if float-p 0.0 0))))
          (apply (defsum-names name "-BUILD") (append values (list s) dims))
          (dotimes (trial 40)
            (let* ((lohis (mapcan (lambda (d)
                                    (let* ((lo (rnd d))
                                           (hi (+ lo (rnd (- d lo)))))
                                      (list lo hi)))
                                  dims))
                   (q (apply (defsum-names name "-QUERY") s (append dims lohis)))
                   (v (apply (defsum-names name "-NAIVE") (append values lohis))))
              (unless (if float-p (< (abs (- q v)) 1e-6) (eql q v))
                (error "defsum ~a: the derived table answers ~a where the sum ~
                        itself gives ~a, at box ~a -- the generated code does ~
                        not implement the recurrence"
                       name q v lohis)))))))
    t))

(defvar *introspect-loaded* nil)

(defun derive-type (form)
  "What SBCL makes of a DEFUN, once it has compiled it.

Only pure Common Lisp can be evaluated here -- a function reaching into
Python does not exist in this image -- so failure is expected and silent.
What comes back is the whole ftype: argument types the programmer declared,
and the return type SBCL worked out from them.  The return type is the part
worth having.  It is free, it is sound, and it says things a declaration does
not: that (expt 2 (- n)) over an integer yields a RATIONAL, which is exactly
the value machine integers cannot hold."
  (unless *introspect-loaded*
    (ignore-errors (require :sb-introspect))
    (setf *introspect-loaded* t))
  (ignore-errors
    (let ((name (second form)))
      (when (and (symbolp name) (not (null name)))
        (handler-bind ((warning #'muffle-warning))
          (eval form))
        (let ((ftype (funcall (find-symbol "FUNCTION-TYPE" "SB-INTROSPECT") name)))
          (when (and (consp ftype) (eq (first ftype) 'function))
            (list name (third ftype))))))))

;;; ------------------------------------------------------------------
;;; Lifting a loop back to the sum it computes.
;;;
;;; DEFSUM takes the specification and derives the implementation.  This goes
;;; the other way, for code that was already written as the naive nest:
;;;
;;;     (dotimes (i n)
;;;       (let ((acc 0.0))
;;;         (dotimes (a (+ i 1)) (setq acc (+ acc (aref v a))))
;;;         (setf (aref ps i) acc)))
;;;
;;; That is sum(v[a], a, 0, i) stored into ps[i], written in O(n^2).  What it
;;; specifies has a running-sum implementation, and the recurrence behind it
;;; is the one DEFSUM derives.
;;;
;;; Two things make this safe to do at all.  The rewrite is opt-in, because
;;; whether the array is finished being written before it is read is a
;;; property no recogniser can see.  And it is verified rather than trusted:
;;; both versions are run here, on random data, and the rewrite is discarded
;;; if they disagree.

(defun dotimes-form-p (form)
  (and (consp form) (symbolp (car form))
       (string= (symbol-name (car form)) "DOTIMES")
       (consp (second form))))

(defun setf-aref-p (form)
  (and (consp form) (symbolp (car form))
       (string= (symbol-name (car form)) "SETF")
       (consp (second form)) (symbolp (car (second form)))
       (string= (symbol-name (car (second form))) "AREF")))

(defun plus-one-p (form var)
  "Is FORM the expression (+ VAR 1), however it is spelled?"
  (and (consp form) (symbolp (car form))
       (or (and (string= (symbol-name (car form)) "+")
                (or (and (eq (second form) var) (eql (third form) 1))
                    (and (eql (second form) 1) (eq (third form) var))))
           (and (string= (symbol-name (car form)) "1+")
                (eq (second form) var)))))

(defun match-prefix-nest (form)
  "Recognise the naive prefix-sum nest and take it apart.

Returns (outer bound acc init inner summand target) or NIL.  The summand may
use the inner index but not the outer one: if it uses the outer index the sum
is not a prefix sum of a fixed sequence and the rewrite does not apply."
  (when (dotimes-form-p form)
    (destructuring-bind ((outer bound &optional res) &rest body) (rest form)
      (declare (ignore res))
      (let ((body (remove nil body)))
        (when (and (= (length body) 1) (consp (first body))
                   (symbolp (car (first body)))
                   (string= (symbol-name (car (first body))) "LET"))
          (destructuring-bind (bindings &rest let-body) (rest (first body))
            (when (and (= (length bindings) 1) (= (length let-body) 2))
              (let ((acc (first (first bindings)))
                    (init (second (first bindings)))
                    (loop-form (first let-body))
                    (store (second let-body)))
                (when (and (dotimes-form-p loop-form) (setf-aref-p store))
                  (destructuring-bind ((inner limit &optional r2) &rest inner-body)
                      (rest loop-form)
                    (declare (ignore r2))
                    (let ((inner-body (remove nil inner-body)))
                      (when (and (plus-one-p limit outer)
                                 (= (length inner-body) 1))
                        (let ((step (first inner-body)))
                          (when (and (consp step) (symbolp (car step))
                                     (string= (symbol-name (car step)) "SETQ")
                                     (eq (second step) acc)
                                     (consp (third step))
                                     (string= (symbol-name (car (third step))) "+")
                                     (eq (second (third step)) acc))
                            (let ((summand (third (third step)))
                                  (target (second (second store))))
                              (when (and (eq (third (second store)) outer)
                                         (eq (third store) acc)
                                         (not (occurs-p outer summand)))
                                (list outer bound acc init inner summand
                                      target)))))))))))))))))

(defun occurs-p (sym form)
  (cond ((eq sym form) t)
        ((consp form) (or (occurs-p sym (car form)) (occurs-p sym (cdr form))))
        (t nil)))

(defun lift-prefix-nest (form)
  "The same computation as a running sum, or NIL if the shape does not match."
  (let ((m (match-prefix-nest form)))
    (when m
      (destructuring-bind (outer bound acc init inner summand target) m
        (declare (ignore acc))
        ;; S(i) = S(i-1) + f(i), with S(0) = init + f(0)
        (let ((at-outer (subst outer inner summand)))
          `(dotimes (,outer ,bound)
             (setf (aref ,target ,outer)
                   (+ ,at-outer
                      (if (> ,outer 0)
                          (aref ,target (- ,outer 1))
                          ,init)))))))))

(defun lift-walk (form)
  "Rewrite every prefix-sum nest in FORM, and report how many."
  (let ((n 0))
    (labels ((walk (x)
               (cond ((not (consp x)) x)
                     ((lift-prefix-nest x) (incf n) (lift-prefix-nest x))
                     (t (cons (walk (car x)) (walk (cdr x)))))))
      (values (walk form) n))))

(defun lift-check (original lifted params)
  "Run both versions here, on random data, and require them to agree.

The rewrite is a change of algorithm, so it is not enough that it looks
right.  PARAMS names the arrays the loops write; each is allocated twice, the
two versions are run side by side, and disagreement rejects the rewrite."
  (let ((seed 20260804))
    (flet ((rnd () (setf seed (mod (+ (* seed 1103515245) 12345) 2147483648))
                   (- (/ (float (mod seed 2000)) 1000.0) 1.0)))
      (let* ((n 12)
             (v (make-array n)))
        (dotimes (i n) (setf (aref v i) (rnd)))
        (let ((a (make-array n :initial-element 0.0))
              (b (make-array n :initial-element 0.0)))
          (handler-case
              (progn
                (funcall (compile nil `(lambda (,@params) ,original)) v a n)
                (funcall (compile nil `(lambda (,@params) ,lifted)) v b n)
                (dotimes (i n t)
                  (when (> (abs (- (aref a i) (aref b i))) 1d-9)
                    (return nil))))
            (error () nil)))))))

(defmacro cl-user::lift-sums (&body body)
  "Rewrite the naive prefix-sum nests in BODY as running sums.

Opt-in, because whether an array is finished being written before it is read
is a property no recogniser can see.  Verified before it is accepted: both
versions are run in this image and must agree."
  (multiple-value-bind (lifted count) (lift-walk (cons 'progn body))
    (if (zerop count)
        (cons 'progn body)
        lifted)))

(defmacro cl-user::defsum (name axes summand
                           &key (element-type 'cl-user::double-float))
  "Define NAME-BUILD, NAME-QUERY and NAME-NAIVE from a box-sum specification.

AXES is ((run-index query-bound dimension) ...).  The recurrence behind the
table is derived by telescoping the sum in Maxima and the generated code is
checked against the naive sum before it is accepted."
  (unless (defsum-telescopes-p axes summand)
    (error "defsum ~a: the sum does not telescope, so no summed-area table ~
            computes it.  The summand may use the running indices ~a but not ~
            the bounds ~a."
           name (mapcar #'first axes) (mapcar #'second axes)))
  (multiple-value-bind (build query naive)
      (gen-defsum name axes summand element-type)
    (defsum-selfcheck name build query naive axes summand element-type)
    `(progn ,build ,query ,naive)))

(import '(lift-prefix-nest lift-walk lift-check llm-ask
          maxima-diff maxima-integrate maxima-simplify maxima-expand
          maxima-factor maxima-apply lisp->maxima maxima->lisp
          maxima-taylor maxima-optimize maxima-horner maxima-solve
          maxima-provable-p maxima-solve-rec)
        :common-lisp-user)

;; Loaded as a script, start serving.  Setting HYCLB_BUILD_CORE loads the
;; bridge without serving, which is what building a core image would need.
(unless (equal (sb-ext:posix-getenv "HYCLB_BUILD_CORE") "1")
  (serve))
