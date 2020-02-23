
(import sys)
(import re)
(import numpy)
(import importlib.machinery)
(import importlib.util)


(import [fractions [Fraction]])

(import hy)
(import [hy.contrib.hy-repr [hy-repr]])

;;(import  [hyclb.core [cons cdr]])

;;(eval-and-compile
(import  hyclb.core)
;;  )
(require hyclb.core)

(import cl4py)
(import [cl4py.reader [*]]
        [cl4py.data [*]]
        [cl4py.circularity  [*]]
        )

;;(setv hyclb.cl4hy-loaded True)
;;(eval-and-compile
(import cl4py)

(defn single_quote [r s c] (quote (r.read_aux s) ))  ;;  return Cons("COMMON-LISP:QUOTE", Cons(r.read_aux(s), None))
(defn sharpsign_m [r s c n]
  (setv data  (r.read_aux s))
  ;;(print "sharpsign_m" data)
  (setv name   (hyclb.core.car data)
        alist  (hyclb.core.cdr data)
        spec   (importlib.machinery.ModuleSpec name None)
        module (importlib.util.module_from_spec spec)
        module.__class__  Package)
  ;;# Now register all exported functions.
  (for [cons1  alist]
    (setattr module
             (. (hyclb.core.car cons1) python_name)
             ;;cons.car.python_name
             (hyclb.core.cdr cons1)
             ))
  module)
(defn sharpsign_colon [r s c n]   ;;gensym var
  (setv data (r.read_aux s))
  ;;(print "sharpsign_colon" data)
  (hy.models.HySymbol (+ "_G" data)))

(defn sharpsign [r s c]
  (setv digits  "")
  (while True
    (setv c  (s.read_char))
    (if (c.isdigit)
        (+= digits c)
        (do 
          (setv c  (c.upper))
          (break))))
  (setv n (if digits (int digits) 0))
  ((r.get_dispatch_macro_character "#" c) r s c n))


(defclass ReadtableHy [cl4py.reader.Readtable]
  (defn __init__ [self lisp]
    (.__init__ (super) lisp)
    (self.set_macro_character "'" single_quote)
    (self.set_macro_character "#" sharpsign)
    (self.set_dispatch_macro_character "#" "M" sharpsign_m)
    (self.set_dispatch_macro_character "#" ":" sharpsign_colon)
    )
  
  (defn read_aux [self stream]
    (while True
      ;;# 1. read one character
      (setv x (stream.read_char) syntax_type (self.syntax_type x))
      ;;(print x syntax_type)
      (cond
        ;;# 3. whitespace
        [(= syntax_type cl4py.reader.SyntaxType.WHITESPACE) (continue)]
        ;;# 4. macro characters
        [(or (= syntax_type cl4py.reader.SyntaxType.TERMINATING_MACRO_CHARACTER)
             (= syntax_type cl4py.reader.SyntaxType.NON_TERMINATING_MACRO_CHARACTER))
         (do
           ;;(print (self.get_macro_character x))
           (setv value ((self.get_macro_character x) self stream x))
           (lif-not value (continue) (return value)))]
        ;;# 5. single escape character
        [(= syntax_type cl4py.reader.SyntaxType.SINGLE_ESCAPE)
         (setv token [(stream.read_char)]  escape False)]
        ;;# 6. multiple escape character
        [(= syntax_type cl4py.reader.SyntaxType.MULTIPLE_ESCAPE)
         (setv token  []                escape  True)]
        ;;# 7. constituent character
        ;;[True  (setv token [(x.upper)]  escape False)])
        [True  (setv token [x]  escape False)])
      ;;(print token)
      (while True
        (setv y  (stream.read_char False))
        (if (not y) (break))
        (setv syntax_type  (self.syntax_type y))
        ;;(print  escape y syntax_type)
        (if (not escape)
            (cond
              ;;# 8. even number of multiple escape characters
              [(= syntax_type cl4py.reader.SyntaxType.SINGLE_ESCAPE) (token.append (stream.read_char))]
              [(= syntax_type cl4py.reader.SyntaxType.MULTIPLE_ESCAPE)  (setv escape True)]
              [(= syntax_type cl4py.reader.SyntaxType.TERMINATING_MACRO_CHARACTER)
               (do  (stream.unread_char) (break))]
              [(= syntax_type cl4py.reader.SyntaxType.WHITESPACE) (do (stream.unread_char)(break))]
              ;;[True  (token.append (y.upper))]
              [True  (token.append y)]
              )
            (cond
              ;;# 9. odd number of multiple escape characters
              [(= syntax_type cl4py.reader.SyntaxType.SINGLE_ESCAPE) (token.append (stream.read_char))]
              [(= syntax_type cl4py.reader.SyntaxType.MULTIPLE_ESCAPE)(setv  escape  False)]
              [True (token.append y)])))
      
      ;;(print token)
      ;;# 10.
      ;; (setv ret (self.parse (.join "" token)))
      ;; (print "ret" ret)
      ;; (return ret)
      (return (self.parse (.join "" token)))
      ;;(return (.join "" token)))
      ))

  (defn parse [self token]
    ;;(print "parse" token)
    ;;# integer
    (setv m  (re.fullmatch cl4py.reader.integer_regex token))
    (if m  (return (int (m.group 0))))
    ;;# ratio
    (setv m  (re.fullmatch cl4py.reader.ratio_regex token))
    (if m (return (Fraction (int (m.group 1)) (int (m.group 2)))))
    ;;# float
    (setv m  (re.fullmatch  cl4py.reader.float_regex token))
    (if m
        (do
          (setv base  (m.group 1)
                exponent_marker (m.group 2)
                exponent  (m.group 3))
          (cond
            [(not exponent_marker)
             (return (* (numpy.float32 base) (** (numpy.float32 10) (numpy.float32 exponent))))]
            [(in exponent_marker "sS")
             (return (* (numpy.float16 base) (** (numpy.float16 10) (numpy.float16 exponent))))]
            [(in exponent_marker "eEfF")
             (return (* (numpy.float32 base) (** (numpy.float32 10) (numpy.float32 exponent))))]
            [(in exponent_marker "dD")
             (return (* (numpy.float64 base) (** (numpy.float64 10) (numpy.float64 exponent))))]
            [(in exponent_marker "lL")
             (return (* (numpy.float128 base) (** (numpy.float128 10) (numpy.float128 exponent))))]
            )))
    
    ;;# symbol
    (setv m (re.fullmatch cl4py.reader.symbol_regex token))
    ;;(print "symbol?" m)
    (if m
        (do
          ;;(print "in symbol ")
          (setv package  (m.group 1)
                delimiter (m.group 2)
                name  (m.group 3))
          ;;(print "symbol=" package delimiter name  (.upper name) )
          ;;(if (= (.upper name) "NAN") (return numpy.nan))
          (if (= (.upper name) "T"  ) (return True))
          (if (= (.upper name) "NIL") (return '()))
          ;; (if (in (.upper package) ["CL" "COMMON-LISP"])
          ;;     (return (hy.models.HySymbol name)))
          ;; (if package
          ;;     (if delimiter                (if delimiter
          ;; (return (hy.models.HySymbol (+ package "::" name))))))
          (if (not package)
              (if delimiter
                  (return (hy.models.HyKeyword name))
                  (return (hy.models.HySymbol name)))
              ;;(return (hy.models.HySymbol (+ name ":" self.lisp.package)))
              (if (in (.upper package)
                      ["CL" "COMMON-LISP" "CL4PY" ]
                                ;["CL" "COMMON-LISP" ]                        
                      )
                  (return (hy.models.HySymbol (.lower name)))
                  (return (hy.models.HySymbol
                            (.lower
                              (+ package ":" name))
                            ;; (.replace 
                            ;;   (+ package "." name)
                            ;;   ":" ".")
                            ))))))
    ;;     (do 
    ;;       (if (= (.upper name) "T"  ) (return True))
    ;;       (if (= (.upper name) "NIL") (return '()))))
    ;; (return (hy.models.HySymbol (+ name ":" package))))))
    (raise (RuntimeError (+ "Failed to parse token " token)))
    )

  
  (defn read_delimited_list [self delim stream recursive]
    ;;(print "read_delimited_list"  delim stream recursive)
    (defn skip_whitespace []
      (while True
        (setv x (stream.read_char))
        (if (!= (self.syntax_type x) cl4py.reader.SyntaxType.WHITESPACE)
            (do (stream.unread_char) (break)))))
    
    (defn tail_add [head delim]
      (skip_whitespace)
      (setv x (stream.read_char))
      (cond
        [(= x  delim)
         (do
           ;;(print head)
           ;;(hyclb.core.cdr head)
           head
           )
           ]
        [(= x ".")
         (do
           (setv e (self.read stream True))
                                ;(print "dot" e)
           ;;(setv head (hyclb.core.cons head e))
           ;;(tail_add head delim)
           (tail_add (hyclb.core.cons head e) delim)
           )
         ]
        [True
         (do
           (stream.unread_char)
           (setv e (self.read stream True))
                                ;(print "+" head e)
           ;;(setv head (hyclb.core.cons head [e]))
           ;;(tail_add (hyclb.core.nconc head `(~e)) delim)
           ;; (print "nconc"
           ;;        (hy-repr (hyclb.core.nconc head `(~e)))
           ;;        (hy-repr head)
           ;;        (hy-repr `(~e))
           ;;        )
           (tail_add (hyclb.core.nconc head `(~e)) delim)
           ;;(tail_add (hyclb.core.nconc head [e]) delim)
           )
         ]))
    ;; (setv ret     (tail_add '() delim) )
    ;; (print "ret "ret)
    ;; ret
    (tail_add '() delim)
    ;;(tail_add [] delim)      
    )
  )



(defclass Clisp [cl4py.lisp.Lisp]
  (defn __init__ [self &optional [cmd ["sbcl" "--script"]] [quicklisp False]]
    (.__init__ (super) cmd quicklisp)
    
    (setv self.readtable  (ReadtableHy self))
    )

  (defn __del__ [self]
    (try
      (self.stdin.write "(cl-user:quit)\n")
      (except []  None )  ))
  
  (defn eval_str [self expr ]
    ;;(setv sexp (hy-repr expr))
    (setv sexp expr)
    ;;(print sexp)
    ;;(print "eval_str" (hy-repr sexp))
                                ;(if self.debug (print sexp))
    (self.stdin.write (+ sexp "\n"))
    (setv pkg (self.readtable.read self.stdout))
    ;;(print "pkg" (hy-repr pkg))
    (setv val (self.readtable.read self.stdout))
    ;;(print "val" (hy-repr val))
    (setv err (self.readtable.read self.stdout))
    ;;(print "err" (hy-repr err))
    (setv msg (self.readtable.read self.stdout))
    ;;(print "msg" (hy-repr msg))

    
    ;;(print pkg val err msg)
    
    ;;# Update the current package.
    ;;(setv self.package  pkg)
    ;;# Write the Lisp output to the Python output.
    ;;(print msg end="")
    ;;# If there is an error, raise it.
    ;; if isinstance(err, Cons):
    ;;         condition = err.car
    ;;         msg = err.cdr.car if err.cdr else ""
    ;;         def init(self):
    ;;             RuntimeError.__init__(self, msg)
    ;;         raise type(str(condition), (RuntimeError,),
    ;;                    {'__init__': init})()
    ;;     # Now, check whether there are any unpatched instances.  If so,
    ;;     # figure out their class definitions and patch them accordingly.
    ;;     items = list(self.unpatched_instances.items())
    ;;     self.unpatched_instances.clear()
    ;;     for (cls_name, instances) in items:
    ;;         cls = type(cls_name.python_name, (LispWrapper,), {})
    ;;         self.classes[cls_name] = cls
    ;;         alist = self.function('cl4py:class-information')(cls_name)
    ;;         for cons in alist:
    ;;             add_member_function(cls, cons.car, cons.cdr)
    ;;         for instance in instances:
    ;;             instance.__class__ = cls
    ;;     # Finally, return the resulting values.
    ;;     if val == ():
    ;;         return None
    ;;     elif val.cdr == ():
    ;;         return val.car
    ;;     else:
    ;;         return tuple(val)

    (first val)
    ;;val
    )

  (defn eval_qexpr [self qexpr]
    (setv exs (cut (hy-repr qexpr) 1 None))
    ;;(print exs)
    (self.eval_str exs)
    )
  )

(setv clisp (Clisp :quicklisp True))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;pre load packages 

(clisp.eval_qexpr '(ql:quickload "alexandria"))
;;(clisp.eval_qexpr '(rename-package 'alexandria 'alex))
;;(clisp.eval_qexpr '(sb-ext:unlock-package 'alexandria))

(clisp.eval_qexpr '(ql:quickload "anaphora"))
(clisp.eval_qexpr '(rename-package 'anaphora 'ap) )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defmacro ap:ignore-first [&rest args]
  (if (= (len args)  2)
      (get args 1)
      (cut args 1 None)
  ))



(import [hy.contrib.walk [postwalk prewalk]])

(setv cl-imported-keywords
      ["let*" "progn" "progn" "identity"
       "ap:it" "ap:ignore-first"
       ]
      )

(setv element-renames
      {
       'nil 'nil/cl
       'null 'null/cl
       'if 'if/cl
       'cond 'cond/cl
       'let 'let/cl
       'setq 'setv
       'setf 'setv       
       'atom 'atom/cl
       't True
       'declare   'declare/cl
       'ignorable 'ignorable/cl
       }
      )
(.update element-renames
         (dfor k cl-imported-keywords
               [(hy.models.HySymbol k)
                (hy.models.HySymbol k)]))
(.update element-renames
         (dfor k element-renames
               [(hy.models.HySymbol (.upper (str k)))
                (get element-renames k)]))

(defn q-element-cl-replace [p]
  ;;(print "q-element-cl-replace" p)
  (if (symbol? p)
      (if (in p element-renames)
          (get element-renames p)
          ;;(hy.models.HySymbol  (.replace  (str p) ":" ".") )
          p
          )
      p))

(defn q-exp-cl-rename-deep [p];; &optional [clisp clisp]]
  ;;(print "q-exp-cl-rename-deep" (hy-repr p))
  (postwalk q-element-cl-replace p))

(defn q-element-clmc-replace [p]
  ;;(print "q-element-clmc-replace"  (hy-repr p))
  (if (not (coll? p))
      p
      (do
        (setv p1 `(macroexpand '~p))
        ;;(print "p1" (hy-repr p1))
        ;;(setv p2  (hy.models.HyExpression (clisp.eval_qexpr p1)))
        (setv p2  (clisp.eval_qexpr p1))
        ;;(print "p2" (hy-repr p2))
        (lif p2
             (if (and (coll? p2) (empty? p2))
              p
              p2)
          p)
        )))

(defn q-exp-clmc-rename-deep [p];; &optional [clisp clisp]]
  (prewalk q-element-clmc-replace p))

;; (defmacro labels [name arg &rest code]
;;   `(defn ~name [~@arg]
;;      ~@(lfor p code (q-exp-cl-rename-deep p)))
;;      )

(defmacro defun [name arg &rest code]
  ;;(print "defun" name)
  `(defn ~name [~@arg]
     ~@(lfor p code
             (do
               (setv ret1 (q-exp-clmc-rename-deep p) )
               ;(print "ret1" (hy-repr ret1))
               (setv ret2 (q-exp-cl-rename-deep ret1)) 
               ;(print "ret2" (hy-repr ret2))
               ret2
               ))))



