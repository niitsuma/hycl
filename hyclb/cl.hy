;;;; The Common Lisp special operators, as Hy macros.
;;;;
;;;; Everything SBCL hands back reduces to these plus function calls, so this
;;;; file is the whole of the language surface.  Binding forms and control
;;;; structures deliberately expand inline -- never into a nested function --
;;;; so that `yield`, `await` and `continue` still work through them.
;;;;
;;;; The runtime is deliberately *not* imported here: these macros expand into
;;;; the module being compiled, which imports it itself.  Pulling it in would
;;;; also shadow `hy.models.Symbol` with the Common Lisp symbol class.

(eval-and-compile
  (import hy)
  (import hy.models :as hym))

;; ---------------------------------------------------------------- trivia

(defmacro cl-declare [#* _] 'None)

(defmacro cl-if [test then #* else]
  `(if (truthy ~test) ~then ~(if else (get else 0) 'NIL)))

(defmacro cl-setq [#* pairs]
  (setv out [])
  (for [i (range 0 (len pairs) 2)]
    (.append out `(setv ~(get pairs i) ~(get pairs (+ i 1)))))
  `(do ~@out ~(if pairs (get pairs (- (len pairs) 2)) 'NIL)))

;; ---------------------------------------------------------------- binding

(eval-and-compile
  (defn split-bindings [bindings]
    "((x 1) y (z 3)) -> [[x init] ...], with a missing init meaning NIL."
    (setv out [])
    (for [b bindings]
      (if (isinstance b hym.Symbol)
          (.append out #(b 'NIL))
          (.append out #((get b 0) (if (> (len b) 1) (get b 1) 'NIL)))))
    out)

  (defn interleave [pairs]
    (setv out [])
    (for [p pairs] (.extend out p))
    out))

(defmacro cl-let [bindings #* body]
  ;; CL's LET evaluates every init before binding anything, so the inits go
  ;; through temporaries first.
  (setv pairs (split-bindings bindings))
  (setv tmps (lfor _ pairs (hy.gensym)))
  `(let [~@(interleave (lfor [t p] (zip tmps pairs) #(t (get p 1))))
         ~@(interleave (lfor [t p] (zip tmps pairs) #((get p 0) t)))]
     ~@body))

(defmacro cl-let-star [bindings #* body]
  `(let [~@(interleave (split-bindings bindings))] ~@body))

;; ---------------------------------------------------------------- functions

(eval-and-compile
  (defn lambda-list [ll]
    "Translate a CL lambda list into Hy parameters, and name the &rest arg.

    Returns #(params rest-name).  CL binds &rest to a list, so the caller
    rebinds Python's tuple as a cons chain."
    (setv out [] mode "required" restname None)
    (for [p ll]
      (setv s (str p))
      (cond
        (= s "&optional") (setv mode "optional")
        (or (= s "&rest") (= s "&body")) (setv mode "rest")
        (= s "&aux") (setv mode "aux")
        (= s "&py-rest") (setv mode "py-rest")
        (= s "&py-kwargs") (setv mode "py-kwargs")
        (= s "&py-kwonly")
        (do (setv mode "py-kwonly")
            ;; a bare * marker, when there is no *args to separate on
            (when (not (any (gfor x out (and (isinstance x hym.Expression)
                                             (= (str (get x 0)) "unpack-iterable")))))
              (.append out (hym.Symbol "*"))))
        (= mode "required") (.append out p)
        (= mode "optional")
        (.append out (if (isinstance p hym.Symbol)
                         (hym.List [p 'NIL])
                         (hym.List [(get p 0)
                                    (if (> (len p) 1) (get p 1) 'NIL)])))
        (= mode "rest")
        (do (setv restname p)
            (.append out (hym.Expression [(hym.Symbol "unpack-iterable") p])))
        ;; Python-shaped parameters, for code that came from Python.  &py-rest
        ;; is Python's *args and stays a tuple -- unlike CL's &rest, which is a
        ;; list -- so it is not fixed up afterwards.
        (= mode "py-rest")
        (.append out (hym.Expression [(hym.Symbol "unpack-iterable") p]))
        (= mode "py-kwargs")
        (.append out (hym.Expression [(hym.Symbol "unpack-mapping") p]))
        (= mode "py-kwonly")
        (.append out (if (isinstance p hym.Symbol)
                         p
                         (hym.List [(get p 0)
                                    (if (> (len p) 1) (get p 1) 'NIL)])))
        True None))
    #(out restname)))

(eval-and-compile
  (defn rest-fixup [restname body]
    "CL's &rest is a list; Python hands us a tuple."
    (if restname
        [`(let [~restname (from-py (list ~restname))] ~@body)]
        body)))

(defmacro cl-lambda [ll #* body]
  (setv [params restname] (lambda-list ll))
  `(fn [~@params] ~@(rest-fixup restname body)))

(defmacro cl-function [f] f)

(defmacro cl-defun [name ll #* body]
  (setv [params restname] (lambda-list ll))
  `(defn ~name [~@params]
     ~@(rest-fixup restname [`(cl-block ~name ~@body)])))

(defmacro cl-flet [bindings #* body]
  `(do ~@(lfor b bindings
               `(defn ~(get b 0) [~@(get (lambda-list (get b 1)) 0)]
                  ~@(rest-fixup (get (lambda-list (get b 1)) 1) (cut b 2 None))))
       ~@body))

(defmacro cl-labels [bindings #* body]
  `(cl-flet ~bindings ~@body))

;; ---------------------------------------------------------------- exits

(defmacro cl-block [name #* body]
  `(try
     (do ~@body)
     (except [e BlockExit]
       (if (= (. e name) ~(str name)) (. e value) (raise)))))

(defmacro cl-return-from [name #* value]
  `(raise (BlockExit ~(str name) ~(if value (get value 0) 'NIL))))

(defmacro cl-unwind-protect [protected #* cleanup]
  `(try ~protected (finally ~@cleanup)))

;; ---------------------------------------------------------------- tagbody
;;
;; TAGBODY becomes a `while` dispatching on a state variable, so a backward GO
;; is a plain jump rather than a tail call.  Expanding it into nested
;; functions instead -- the obvious encoding, and the one the 2020 version of
;; this system used -- costs a Python stack frame per iteration and dies at
;; the recursion limit after a thousand of them.

(eval-and-compile
  (defn tagbody-tags [body]
    (lfor f body :if (isinstance f hym.Symbol) (str f)))

  (defn jump [st n]
    (hym.Expression [(hym.Symbol "do")
                     (hym.Expression [(hym.Symbol "setv") st (hym.Integer n)])
                     (hym.Expression [(hym.Symbol "continue")])]))

  (defn replace-go [form st tags shadowed]
    "Rewrite (cl-go tag) into a jump, leaving inner tagbodies' tags alone."
    (cond
      (not (isinstance form hym.Expression)) form
      (= (len form) 0) form
      (and (isinstance (get form 0) hym.Symbol)
           (= (str (get form 0)) "cl-go")
           (= (len form) 2)
           (in (str (get form 1)) tags)
           (not (in (str (get form 1)) shadowed)))
      (jump st (get tags (str (get form 1))))
      True
      (do
        (setv inner shadowed)
        (when (and (isinstance (get form 0) hym.Symbol)
                   (= (str (get form 0)) "cl-tagbody"))
          (setv inner (| shadowed (set (tagbody-tags (cut form 1 None))))))
        (hym.Expression (lfor x form (replace-go x st tags inner)))))))

(defmacro cl-tagbody [#* body]
  (setv st (hy.gensym "state"))
  (setv segments [[]] tags {})
  (for [f body]
    (if (isinstance f hym.Symbol)
        (do (setv (get tags (str f)) (len segments))
            (.append segments []))
        (.append (get segments (- (len segments) 1)) f)))
  (setv n (len segments))
  (defn dispatch [i]
    (if (>= i n)
        `(break)
        `(if (= ~st ~(hym.Integer i))
             (do ~@(lfor f (get segments i) (replace-go f st tags (set)))
                 (setv ~st ~(hym.Integer (+ i 1))))
             ~(dispatch (+ i 1)))))
  `(do
     (setv ~st 0)
     (while True ~(dispatch 0))
     NIL))

(defmacro cl-go [tag]
  `(cl-error ~(+ "GO outside of its TAGBODY: " (str tag))))

;; ---------------------------------------------------------------- values

(defmacro cl-multiple-value-bind [names expr #* body]
  (setv extra (hy.gensym "extra"))
  `(let [~(get names 0) ~expr
         ~extra (cl-extra-values)
         ~@(interleave
             (lfor [i n] (enumerate (cut names 1 None))
                   #(n `(if (> (len ~extra) ~(hym.Integer i))
                            (get ~extra ~(hym.Integer i))
                            NIL))))]
     ~@body))

;; ---------------------------------------------------------------- places
;;
;; SBCL expands these into its own internal arithmetic, so they sit on the
;; expansion frontier and are translated here instead.

(defmacro cl-incf [place #* delta]
  `(do (setv ~place (+ ~place ~(if delta (get delta 0) 1))) ~place))

(defmacro cl-decf [place #* delta]
  `(do (setv ~place (- ~place ~(if delta (get delta 0) 1))) ~place))

(defmacro cl-push [item place]
  `(do (setv ~place (cl-cons ~item ~place)) ~place))

(defmacro cl-pop [place]
  (setv head (hy.gensym "head"))
  `(let [~head (cl-car ~place)]
     (setv ~place (cl-cdr ~place))
     ~head))

;; ---------------------------------------------------------------- Python

(defmacro cl-py-import [name]
  `(import ~name))

(defmacro cl-py-import-as [name alias]
  `(import ~name :as ~alias))

;; ---------------------------------------------------------------- destructuring
;;
;; SBCL's own expansion calls into its argument checker, so this sits on the
;; frontier.  Required names, &optional and &rest are supported; nested
;; patterns are not yet.

(eval-and-compile
  (defn ds-bindings [pattern src]
    "Bindings for a destructuring lambda list, nested patterns included.

    This is On Lisp's DESTRUC: a sub-pattern binds a temporary and then
    destructures that, so the nesting has no depth limit."
    (setv out [] mode "required" i 0)
    (for [p pattern]
      (setv s (str p))
      (cond
        (= s "&optional") (setv mode "optional")
        (or (= s "&rest") (= s "&body")) (setv mode "rest")
        (= mode "rest") (.extend out [p `(cl-nthcdr ~(hym.Integer i) ~src)])
        (and (isinstance p hym.List) (!= mode "optional"))
        (do
          (setv tmp (hy.gensym "ds"))
          (.extend out [tmp `(cl-nth ~(hym.Integer i) ~src)])
          (.extend out (ds-bindings p tmp))
          (setv i (+ i 1)))
        True
        (do
          (setv name (if (isinstance p hym.Symbol) p (get p 0)))
          (setv default (if (or (isinstance p hym.Symbol) (< (len p) 2))
                            'NIL
                            (get p 1)))
          (.extend out
                   [name (if (= mode "optional")
                             `(if (> (cl-length ~src) ~(hym.Integer i))
                                  (cl-nth ~(hym.Integer i) ~src)
                                  ~default)
                             `(cl-nth ~(hym.Integer i) ~src))])
          (setv i (+ i 1)))))
    out))

(defmacro cl-destructuring-bind [ll expr #* body]
  (setv v (hy.gensym "ds"))
  `(let [~v ~expr ~@(ds-bindings ll v)] ~@body))

;; ---------------------------------------------------------------- with
;;
;; Python's context managers have no Common Lisp counterpart, and UNWIND-PROTECT
;; is not one: the protocol calls __enter__ and __exit__ on the object.

(defmacro cl-py-with [clauses #* body]
  ;; A clause is (var form) when it binds and just a form when it does not.
  ;; Testing for a List rather than for a Symbol matters: the form may be an
  ;; attribute access, which is an Expression, not a symbol.
  `(with [~@(interleave (lfor c clauses
                              (if (isinstance c hym.List)
                                  #((get c 0) (get c 1))
                                  #('_ c))))]
     ~@body))

;; ---------------------------------------------------------------- defstruct

(eval-and-compile
  (defn struct-slots [spec]
    "Slot names and defaults from a DEFSTRUCT body."
    (lfor s spec
          (if (isinstance s hym.Symbol) #(s 'NIL)
              #((get s 0) (if (> (len s) 1) (get s 1) 'NIL)))))

  (defn struct-name [spec]
    (if (isinstance spec hym.Symbol) spec (get spec 0))))

(defmacro cl-defstruct [spec #* body]
  (setv name (struct-name spec))
  (setv slots (struct-slots (lfor s body :if (not (isinstance s hym.String)) s)))
  (setv cls (hy.gensym "struct"))
  `(do
     (setv ~cls (cl-struct-class ~(str name)
                                 [~@(lfor s slots (hy.models.String (str (get s 0))))]
                                 [~@(lfor s slots (get s 1))]))
     (defn ~(hym.Symbol (+ "make-" (str name))) [#* a] (cl-make-struct ~cls #* a))
     (defn ~(hym.Symbol (+ (str name) "-p")) [o] (cl-struct-p o ~cls))
     (defn ~(hym.Symbol (+ "copy-" (str name))) [o] (cl-copy-struct o))
     ~@(lfor s slots
             `(defn ~(hym.Symbol (+ (str name) "-" (str (get s 0)))) [o]
                (cl-slot o ~(hy.models.String (str (get s 0))))))
     ~@(lfor s slots
             `(defn ~(hym.Symbol (+ "set-" (str name) "-" (str (get s 0)))) [o v]
                (cl-set-slot o ~(hy.models.String (str (get s 0))) v)))
     ~cls))

;; ---------------------------------------------------------------- CLOS
;;
;; Classes map onto Python classes so instances interoperate, but generic
;; functions cannot: Python dispatches on the receiver alone.  The method
;; table therefore lives in the runtime, which ranks candidates by MRO
;; distance across every specialised argument.

(eval-and-compile
  (defn slot-spec [s]
    "(name :initform x :accessor f :type integer) -> #(name init accessors type)"
    (if (isinstance s hym.Symbol)
        #(s 'NIL [] 'NIL)
        (do
          (setv name (get s 0) init 'NIL acc [] declared 'NIL i 1)
          (while (< (+ i 1) (len s))
            (setv k (str (get s i)) v (get s (+ i 1)))
            (cond
              (in k [":initform" "initform"]) (setv init v)
              (in k [":accessor" "accessor" ":reader" "reader"]) (.append acc v)
              (in k [":type" "type"]) (setv declared v)
              True None)
            (setv i (+ i 2)))
          #(name init acc declared)))))

(defmacro cl-defclass [name supers slots #* options]
  (setv specs (lfor s slots (slot-spec s)))
  `(do
     (setv ~name
           (cl-register-class
             ~(str name)
             (cl-defclass-impl
               ~(str name)
               (cl-list ~@supers)
               (cl-list ~@(lfor s specs
                                `(cl-list ~(hy.models.String (str (get s 0)))
                                          ~(get s 1)
                                          ~(if (= (str (get s 3)) "NIL")
                                               'NIL
                                               (hy.models.String
                                                 (str (get s 3))))))))))
     ~@(lfor s specs
             (lfor a (get s 2)
                   `(do
                      (cl-add-method (cl-generic ~(str a))
                                     (cl-list ~name) NIL
                                     (fn [o] (cl-slot-value o ~(hy.models.String (str (get s 0))))))
                      (setv ~a (cl-generic ~(str a)))
                      (defn ~(hym.Symbol (+ "set-" (str a))) [o v]
                        (cl-set-slot-value o ~(hy.models.String (str (get s 0))) v)))))
     ~name))

(defmacro cl-defmethod [name #* rest]
  ;; (defmethod name [qualifier] (specialised-lambda-list) body...)
  (setv qual 'NIL i 0)
  (when (isinstance (get rest 0) hym.Symbol)
    (setv qual (hy.models.String (str (get rest 0))) i 1))
  (setv ll (get rest i) body (cut rest (+ i 1) None))
  (setv params [] specs [])
  (for [p ll]
    (if (isinstance p hym.Symbol)
        (do (.append params p) (.append specs 'NIL))
        (do (.append params (get p 0)) (.append specs (get p 1)))))
  `(do
     (cl-add-method (cl-generic ~(str name))
                    (cl-list ~@specs)
                    ~qual
                    (fn [~@params] ~@body))
     (setv ~name (cl-generic ~(str name)))))

(defmacro cl-defgeneric [name ll #* options]
  `(setv ~name (cl-generic ~(str name))))

;; ---------------------------------------------------------------- specials
;;
;; A special variable assigned inside a function is a module global; Python
;; needs to be told so before the assignment.  Dynamic rebinding by LET is not
;; implemented.

(defmacro cl-defvar [name #* value]
  `(do (setv ~name ~(if value (get value 0) 'NIL)) '~name))

(defmacro cl-defparameter [name #* value]
  `(do (setv ~name ~(if value (get value 0) 'NIL)) '~name))

(defmacro cl-globals [#* names]
  `(global ~@names))

;; ---------------------------------------------------------------- conditions

(defmacro cl-define-condition [name supers slots #* options]
  `(setv ~name
         (cl-define-condition-impl
           ~(str name)
           (cl-list ~@(lfor s supers (hy.models.String (str s))))
           (cl-list ~@(lfor s slots
                            (do
                              (setv spec (slot-spec s))
                              `(cl-cons ~(hy.models.String (str (get spec 0)))
                                        (cl-cons ~(get spec 1) NIL))))))))

(eval-and-compile
  (defn condition-designator [head]
    "A clause head names one condition type, or several: except (A, B) as e."
    (if (isinstance head hym.List)
        `(cl-condition-class ~@(lfor x head (hym.String (str x))))
        `(cl-condition-class ~(hym.String (str head))))))

(defmacro cl-handler-case [protected #* clauses]
  `(try
     ~protected
     ~@(lfor c clauses
             `(except [~(if (> (len (get c 1)) 0) (get (get c 1) 0) (hy.gensym "c"))
                       ~(condition-designator (get c 0))]
                ~@(cut c 2 None)))))

(defmacro cl-handler-bind [bindings #* body]
  "Run a handler without unwinding first, and decline by returning.

Common Lisp runs a HANDLER-BIND handler in the dynamic context where the
condition was signalled: the stack is still there, which is what lets the
handler pick a restart.  Python has no such thing -- `except` has already
unwound by the time the handler runs -- so what we can honour is the other
half of the contract: a handler that returns normally *declines*, and the
condition keeps going.  A handler that transfers control, by invoking a
restart or by throwing, does so from the handler's own frame rather than the
signalling one.  Section `Limitations` of the paper says so.

  (handler-bind ((error (lambda (c) (invoke-restart 'use-value 0))))
    (compute))"
  (setv e (hy.gensym "condition"))
  `(try
     (do ~@body)
     ~@(lfor b bindings
             `(except [~e (cl-condition-class
                            ~(hy.models.String (str (get b 0))))]
                (cl-funcall ~(get b 1) ~e)   ; the binding is a function
                (raise)))))

(defmacro cl-restart-case [protected #* clauses]
  (setv e (hy.gensym "restart"))
  (defn dispatch [i]
    (if (>= i (len clauses))
        `(raise)
        (do
          (setv c (get clauses i))
          `(if (= (. ~e name) ~(hy.models.String (str (get c 0))))
               ((fn [~@(get c 1)] ~@(cut c 2 None)) #* (. ~e args))
               ~(dispatch (+ i 1))))))
  `(do
     (cl-push-restarts [~@(lfor c clauses (hy.models.String (str (get c 0))))])
     (try
       (try ~protected (finally (cl-pop-restarts)))
       (except [~e RestartInvoke] ~(dispatch 0)))))

;; ---------------------------------------------------------------- generators
;;
;; YIELD is why binding forms and control structures must expand inline.  It
;; cannot cross a function boundary, so a LET compiled to an applied lambda,
;; or a TAGBODY compiled to mutually calling functions, would silently break
;; every generator written through them.

(defmacro cl-py-yield [#* value]
  `(yield ~@value))

(defmacro cl-py-yield-from [iterable]
  `(yield :from ~iterable))

(defmacro cl-py-await [expr]
  `(await ~expr))

(defmacro cl-defun-async [name ll #* body]
  (setv [params restname] (lambda-list ll))
  `(defn :async ~name [~@params]
     ~@(rest-fixup restname [`(cl-block ~name ~@body)])))

(defmacro cl-defun-decorated [decorators name ll #* body]
  "(defun/decorated (staticmethod) name (args) ...)"
  (setv [params restname] (lambda-list ll))
  `(defn [~@decorators] ~name [~@params]
     ~@(rest-fixup restname [`(cl-block ~name ~@body)])))

;; ---------------------------------------------------------------- fast path
;;
;; A function declared (optimize (speed 3)) is compiled for numbers only: the
;; conditional tests Python truth, the block wrapper is dropped, and Numba
;; turns the result into machine code.  This is Common Lisp's own safety
;; declaration deciding which of two compilations to use.

(defmacro cl-if-fast [test then #* else]
  `(if ~test ~then ~(if else (get else 0) 'None)))

(defmacro cl-defun-fast [name ll #* body]
  (setv [params restname] (lambda-list ll))
  `(defn [numba-njit] ~name [~@params] ~@body))

;; (optimize (float-accuracy 0)) -- the arithmetic may be reassociated
(defmacro cl-defun-approx [name ll #* body]
  (setv [params restname] (lambda-list ll))
  `(defn [numba-njit-approx] ~name [~@params] ~@body))

;; Iteration compiled directly, for the fast path.  The general expansion goes
;; through TAGBODY and an implicit block; neither survives Numba.

(defmacro cl-dotimes [spec #* body]
  `(do (for [~(get spec 0) (range ~(get spec 1))] ~@body)
       ~(if (> (len spec) 2) (get spec 2) 'None)))

(defmacro cl-dolist [spec #* body]
  `(do (for [~(get spec 0) ~(get spec 1)] ~@body)
       ~(if (> (len spec) 2) (get spec 2) 'None)))

;; ---------------------------------------------------------------- streams

(defmacro cl-cons-stream [head tail]
  "The tail is delayed, as CONS-STREAM has always been."
  `(cl-stream-cons ~head (fn [] ~tail)))

;; ---------------------------------------------------------------- specs
;;
;; A SPEC declaration says what a function may be given, what it returns, and
;; how the two are related.  How much of that is checked at run time is the
;; SAFETY level -- Common Lisp's own dial, rather than a separate switch.

(defmacro cl-defun-checked [name ll level argpreds retpred fnpred #* body]
  (setv [params restname] (lambda-list ll))
  (setv lvl (int level))
  (setv pre [])
  (when (>= lvl 1)
    (for [[i p] (enumerate argpreds)]
      (.append pre
               `(when (not (truthy ~p))
                  (cl-error "spec :args violated in ~a (condition ~a)"
                            (cl-symbol ~(hy.models.String (str name)))
                            ~(hy.models.Integer (+ i 1)))))))
  (setv post [])
  (when (>= lvl 3)
    (when (!= (str retpred) "None")
      (.append post `(when (not (truthy ~retpred))
                       (cl-error "spec :ret violated in ~a: got ~a"
                                 (cl-symbol ~(hy.models.String (str name))) ret))))
    (when (!= (str fnpred) "None")
      (.append post `(when (not (truthy ~fnpred))
                       (cl-error "spec :fn violated in ~a: got ~a"
                                 (cl-symbol ~(hy.models.String (str name))) ret)))))
  `(defn ~name [~@params]
     ~@(rest-fixup restname
         [`(do
             ~@pre
             (setv ret (cl-block ~name ~@body))
             ~@post
             ret)])))

;; (setf (aref v i) x) -- a subscript assignment, so that it survives Numba
(defmacro cl-aset [value array #* index]
  `(do (setv (get ~array ~@index) ~value) ~value))

;; Self-tail recursion.  Python has no tail calls, so a function that calls
;; itself in tail position is compiled as a loop: rebind the parameters and go
;; round again.  The translator marks the tail positions; these three macros
;; are all that is left to do.  Mutual recursion still uses the stack.
(defmacro cl-defun-loop [name ll #* body]
  (setv [params restname] (lambda-list ll))
  `(defn ~name [~@params]
     ~@(rest-fixup restname [`(while True ~@body)])))

(defmacro cl-tail-recur [params #* args]
  ;; simultaneous, as a call would be: every argument is evaluated first
  `(do (setv #(~@params) #(~@args)) (continue)))

(defmacro cl-tail-return [value]
  `(return ~value))

;; Python's AND and OR, for decompiled code: they short-circuit on Python's
;; notion of truth, where Common Lisp's count 0 and the empty list as true.
(defmacro cl-py-and [#* forms] `(and ~@(lfor f forms `(cl-py-truthy-value ~f))))
(defmacro cl-py-or [#* forms] `(or ~@(lfor f forms `(cl-py-truthy-value ~f))))

;; the value is returned, as Python does, but tested Python-style
(defmacro cl-py-truthy-value [form] form)

(defmacro cl-py-global [#* names] `(global ~@names))
(defmacro cl-py-nonlocal [#* names] `(nonlocal ~@names))

;; Python's loops, for decompiled code.  A Python `while` is not CL's LOOP: it
;; must survive the fast path, where the TAGBODY encoding does not, and its
;; break and continue are Python's rather than a block exit and a tag.
(defmacro cl-py-while [test #* body]
  `(while ~test ~@body))

(defmacro cl-py-for [spec #* body]
  `(for [~(get spec 0) ~(get spec 1)] ~@body))

(defmacro cl-py-break [] '(break))
(defmacro cl-py-continue [] '(continue))

(defmacro cl-py-del [#* names] `(del ~@names))

(defmacro cl-py-reraise [] '(raise))
(defmacro cl-py-import-star [module] `(import ~module *))

;; locals() must be evaluated in the frame that has the locals, so it cannot
;; go through py-call: the class-body thunk hands back its own namespace.
(defmacro cl-py-locals [] '(locals))
