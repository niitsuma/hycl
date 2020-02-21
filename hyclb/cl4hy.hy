(import re)
(import numpy)
(import [fractions [Fraction]])

(import hy)
(import [hy.contrib.hy-repr [hy-repr]])

;;(import  [hyclb.core [cons cdr]])

(import  hyclb.core)
(require hyclb.core)

(import cl4py)
(import [cl4py.reader [*]]
        [cl4py.data [*]]
        [cl4py.circularity  [*]]
)

(defclass ReadtableHy [cl4py.reader.Readtable]
  (defn __init__ [self lisp]  (.__init__ (super) lisp) )
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
      (return (self.parse (.join "" token)))
      ;;(return (.join "" token)))
      ))

    (defn parse [self token]
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
                        ["CL" "COMMON-LISP"  "CL4PY" ]
                        ;["CL" "COMMON-LISP" ]                        
                        )
                    (return (hy.models.HySymbol name))
                    (return (hy.models.HySymbol (+ package "::" name)))))))
                ;;     (do 
                ;;       (if (= (.upper name) "T"  ) (return True))
                ;;       (if (= (.upper name) "NIL") (return '()))))
                ;; (return (hy.models.HySymbol (+ name ":" package))))))
      (raise (RuntimeError (+ "Failed to parse token " token)))
      )

    
    (defn read_delimited_list [self delim stream recursive]
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
           ;;(return (hyclb.core.cdr head))
           (hyclb.core.cdr head)
           ;;(return head)
           ;;head
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
             (tail_add (hyclb.core.nconc head [e]) delim))
           ]))
      
      (tail_add [] delim))
           
      ;; (setv head [])
      ;; ;;(setv tail  head)
      ;; (while True
      ;;   (skip_whitespace)
      ;;   (setv x  (stream.read_char))
      ;;   (cond
      ;;     [(= x  delim)
      ;;      (return (hyclb.core.cdr head))
      ;;      ;;(return head)
      ;;      ]
      ;;     [(= x ".")
      ;;      (do
      ;;        (setv e (self.read stream True))
      ;;        (print "dot" e)
      ;;        (setv head (hyclb.core.cons head e))
      ;;        )
      ;;      ]
      ;;     [True
      ;;      (do
      ;;        (stream.unread_char)
      ;;        (setv e (self.read stream True))
      ;;        (print "+" head e)
      ;;        (setv head (hyclb.core.cons head [e])))])))

  )


(defclass Clisp [cl4py.lisp.Lisp]
  (defn __init__ [self &optional [cmd ["sbcl" "--script"]] [quicklisp False]]
    (.__init__ (super) cmd quicklisp)
    (setv self.readtable  (ReadtableHy self))
    )
  
  (defn eval_str [self expr ]
    ;;(setv sexp (hy-repr expr))
    (setv sexp expr)
    (print sexp)
    ;;(print (hy-repr sexp))
    ;(if self.debug (print sexp))
    (self.stdin.write (+ sexp "\n"))
    (setv 
        pkg (self.readtable.read self.stdout)
        val (self.readtable.read self.stdout)
        err (self.readtable.read self.stdout)
        msg (self.readtable.read self.stdout)
        )
    (print pkg val err msg)
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
    (print exs)
    (self.eval_str exs)
    )

  )
