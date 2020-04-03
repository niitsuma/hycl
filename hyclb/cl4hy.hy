
(import sys)
(import re)
(import numpy)


(import reprlib)

(import importlib.machinery)
(import importlib.util)


(import [fractions [Fraction]])

(import hy)
(import [hy.contrib.hy-repr [hy-repr]])

(import [hy.contrib.walk [postwalk prewalk walk]])

;;(import  [hyclb.core [cons cdr]])

(import  [hyclb.models [hyclvector hycllist]] )

;;(eval-and-compile

(import  hyclb.core)
(import [hyclb.core
         [qexp-cl-var-pairs-colon-mod
          qexp-symbol-macrolet-apply-deep
          symbol-macrolet-cl-qexp
          ;;symbol-macrolet-cl-qexp-inner
          qexp-var-pairs-add
          qexp-var-pairs-sub
          vector/cl
          list/cl
          SharpsignSharpsign
          SharpsignEquals
          nil/cl
          ]])


(import  [hyclb.core [q-exp-fn0?]] )
;;  )
(require hyclb.core)


(import cl4py)
(import [gasync.core [q-exp-fn?]])

;;(import [cl4py.reader [*]]
        ;;[cl4py.data [*]]
        ;;[cl4py.circularity  [*]]
;;        )

;;(setv hyclb.cl4hy-loaded True)
;;(eval-and-compile

(defclass Package [(type reprlib)]
  (defn __getitem__ [self name]
    (get self.__dict__ name)))

(defclass Stream [] ;;(LispObject):
  (defn __init__ [self textstream &optional [debug False]]
    (setv self.stream  textstream
          self.old  None
          self.new  None
          self.debug  debug))
  (defn read_char [self  &optional [eof_error True]]
    (if (= self.new  None)
        (do 
          (setv c  (self.stream.read 1))
          ;;(print c)
          (if (and eof_error (not c)) (raise EOFError) )
          ;;(if self.debug ( print c,end='')
          )
        (setv c  self.new))
    (setv self.old c
          self.new None)
    c)
  (defn unread_char [self]
    (if self.old
        (setv self.new self.old
              self.old None )
        (raise (RuntimeError "Duplicate unread_char.")))))

;; (defclass LispWrapper [] ;;(LispObject):
;;   (defn __init__ [self lisp handle]
;;     (setv self.lisp  lisp
;;           self.handle= handle))
;;   (defn __del__ [self]
;;     (try
;;       (self.lisp.eval_str ("'#{}!".format self.handle))
;;       (except [])))
;;   (defn __call__ [self &rest args &kwargs kwargs]
;;     (setv restAndKeys  (lfor arg args `(~arg)))
;;     (for [(, key value) (kwargs.items)]
;;       (restAndKeys.append (keyword key))
;;       (restAndKeys.append `( ~value)))
;;     (self.lisp.eval_str
;;       ;;(List(Symbol('FUNCALL', 'CL'), Quote(self), *restAndKeys))
;;       "(funcall  Quote(self), *restAndKeys))"
;;       )
;;     ))



(defn circularize [obj]
    """Modify and return OBJ, such that each instance of SharpsignEquals or
    SharpsignSharpsign is replaced by the corresponding object.
    """
  (setv table {})
  (defn copy [obj]
    (cond
      [(isinstance obj SharpsignEquals)
       (do  (setv result (copy obj.obj)
                  (get table obj.label) result)
             ;;(print "circularize-cp-obj" (hy-repr result))
            result)]
      [(instance? hyclb.core.ConsPair obj) (hyclb.core.cons (copy obj.car) (copy obj.cdr)) ]
      [(coll? obj)
       (do
         ;;(print "circularize-cp-col" (hy-repr obj))
         ;;(print "circularize-cp-col1" obj)
         (setv ret  ((type obj) (lfor elt obj (copy elt))) )
         ;;(print "circularize-cp-col2" (hy-repr ret))
         ret
         )
       ]      
      [(hyclb.core.cons? obj)
       (do
         ;;(print "circularize-cp-con" (hy-repr obj))
         ((type obj)
           (hyclb.core.cons
             (copy (hyclb.core.car obj))
             (copy (hyclb.core.cdr obj)))))]
      ;;[(coll? obj) ((type obj) (lfor elt obj (copy elt)))]      
      [True
       (do
         ;;(print "circularize-cp-oth" (hy-repr obj))
         obj)
       ]))
  (defn finalize [obj]
    (cond
      [(isinstance obj SharpsignSharpsign) (get table obj.label)]
      [(instance? hyclb.core.ConsPair obj)
       (do (setv c obj.car
                 d obj.cdr)
           (hyclb.core.cons
             (if (isinstance c SharpsignSharpsign)
                 (get table c.label)
                 (finalize c))
             (if (isinstance d SharpsignSharpsign)
                 (get table d.label)
                 (finalize d))))]
      [(coll? obj)
       (do
         ;;(print "circularize-fin-col" (hy-repr obj))
         ((type obj)
           (lfor elt obj
                 (if (isinstance elt SharpsignSharpsign)
                     (get table elt.label)
                     (finalize elt)))))
       ]
      [(hyclb.core.cons? obj)
       (do (setv c (hyclb.core.car obj)
                 d (hyclb.core.cdr obj))
           ;;(print "circularize-fin-con" c d)
           (hyclb.core.cons
             (if (isinstance c SharpsignSharpsign)
                 (get table c.label)
                 (finalize c))
             (if (isinstance d SharpsignSharpsign)
                 (get table d.label)
                 (finalize d))))]
      [True obj]))
    (setv result (copy obj))
    (finalize result))


(setv hy-repr-escape-words ["quasiquote" "unquote-splice" "unquote" "quote" ])
(setv hy-repr-escape-symbols (lfor w hy-repr-escape-words (HySymbol w)))


;;;;https://stackoverflow.com/questions/39560353/common-lisp-keyword-list
;;;; (let (result)    (do-external-symbols (s :common-lisp)     (push s result))   (sort result #'string<))
(setv all-cl-word
      "
 &ALLOW-OTHER-KEYS &AUX &BODY &ENVIRONMENT &KEY &OPTIONAL &REST &WHOLE * ** ***
 *BREAK-ON-SIGNALS* *COMPILE-FILE-PATHNAME* *COMPILE-FILE-TRUENAME*
 *COMPILE-PRINT* *COMPILE-VERBOSE* *DEBUG-IO* *DEBUGGER-HOOK*
 *DEFAULT-PATHNAME-DEFAULTS* *ERROR-OUTPUT* *FEATURES* *GENSYM-COUNTER*
 *LOAD-PATHNAME* *LOAD-PRINT* *LOAD-TRUENAME* *LOAD-VERBOSE* *MACROEXPAND-HOOK*
 *MODULES* *PACKAGE* *PRINT-ARRAY* *PRINT-BASE* *PRINT-CASE* *PRINT-CIRCLE*
 *PRINT-ESCAPE* *PRINT-GENSYM* *PRINT-LENGTH* *PRINT-LEVEL* *PRINT-LINES*
 *PRINT-MISER-WIDTH* *PRINT-PPRINT-DISPATCH* *PRINT-PRETTY* *PRINT-RADIX*
 *PRINT-READABLY* *PRINT-RIGHT-MARGIN* *QUERY-IO* *RANDOM-STATE* *READ-BASE*
 *READ-DEFAULT-FLOAT-FORMAT* *READ-EVAL* *READ-SUPPRESS* *READTABLE*
 *STANDARD-INPUT* *STANDARD-OUTPUT* *TERMINAL-IO* *TRACE-OUTPUT* + ++ +++ - /
 // /// /= 1+ 1- < <= = > >= ABORT ABS ACONS ACOS ACOSH ADD-METHOD ADJOIN
 ADJUST-ARRAY ADJUSTABLE-ARRAY-P ALLOCATE-INSTANCE ALPHA-CHAR-P ALPHANUMERICP
 AND APPEND APPLY APROPOS APROPOS-LIST AREF ARITHMETIC-ERROR
 ARITHMETIC-ERROR-OPERANDS ARITHMETIC-ERROR-OPERATION ARRAY ARRAY-DIMENSION
 ARRAY-DIMENSION-LIMIT ARRAY-DIMENSIONS ARRAY-DISPLACEMENT ARRAY-ELEMENT-TYPE
 ARRAY-HAS-FILL-POINTER-P ARRAY-IN-BOUNDS-P ARRAY-RANK ARRAY-RANK-LIMIT
 ARRAY-ROW-MAJOR-INDEX ARRAY-TOTAL-SIZE ARRAY-TOTAL-SIZE-LIMIT ARRAYP ASH ASIN
 ASINH ASSERT ASSOC ASSOC-IF ASSOC-IF-NOT ATAN ATANH ATOM BASE-CHAR BASE-STRING
 BIGNUM BIT BIT-AND BIT-ANDC1 BIT-ANDC2 BIT-EQV BIT-IOR BIT-NAND BIT-NOR
 BIT-NOT BIT-ORC1 BIT-ORC2 BIT-VECTOR BIT-VECTOR-P BIT-XOR BLOCK BOOLE BOOLE-1
 BOOLE-2 BOOLE-AND BOOLE-ANDC1 BOOLE-ANDC2 BOOLE-C1 BOOLE-C2 BOOLE-CLR
 BOOLE-EQV BOOLE-IOR BOOLE-NAND BOOLE-NOR BOOLE-ORC1 BOOLE-ORC2 BOOLE-SET
 BOOLE-XOR BOOLEAN BOTH-CASE-P BOUNDP BREAK BROADCAST-STREAM
 BROADCAST-STREAM-STREAMS BUILT-IN-CLASS BUTLAST BYTE BYTE-POSITION BYTE-SIZE
 CAAAAR CAAADR CAAAR CAADAR CAADDR CAADR CAAR CADAAR CADADR CADAR CADDAR CADDDR
 CADDR CADR CALL-ARGUMENTS-LIMIT CALL-METHOD CALL-NEXT-METHOD CAR CASE CATCH
 CCASE CDAAAR CDAADR CDAAR CDADAR CDADDR CDADR CDAR CDDAAR CDDADR CDDAR CDDDAR
 CDDDDR CDDDR CDDR CDR CEILING CELL-ERROR CELL-ERROR-NAME CERROR CHANGE-CLASS
 CHAR CHAR-CODE CHAR-CODE-LIMIT CHAR-DOWNCASE CHAR-EQUAL CHAR-GREATERP CHAR-INT
 CHAR-LESSP CHAR-NAME CHAR-NOT-EQUAL CHAR-NOT-GREATERP CHAR-NOT-LESSP
 CHAR-UPCASE CHAR/= CHAR< CHAR<= CHAR= CHAR> CHAR>= CHARACTER CHARACTERP
 CHECK-TYPE CIS CLASS CLASS-NAME CLASS-OF CLEAR-INPUT CLEAR-OUTPUT CLOSE
 CLRHASH CODE-CHAR COERCE COMPILATION-SPEED COMPILE COMPILE-FILE
 COMPILE-FILE-PATHNAME COMPILED-FUNCTION COMPILED-FUNCTION-P COMPILER-MACRO
 COMPILER-MACRO-FUNCTION COMPLEMENT COMPLEX COMPLEXP COMPUTE-APPLICABLE-METHODS
 COMPUTE-RESTARTS CONCATENATE CONCATENATED-STREAM CONCATENATED-STREAM-STREAMS
 COND CONDITION CONJUGATE CONS CONSP CONSTANTLY CONSTANTP CONTINUE
 CONTROL-ERROR COPY-ALIST COPY-LIST COPY-PPRINT-DISPATCH COPY-READTABLE
 COPY-SEQ COPY-STRUCTURE COPY-SYMBOL COPY-TREE COS COSH COUNT COUNT-IF
 COUNT-IF-NOT CTYPECASE DEBUG DECF DECLAIM DECLARATION DECLARE DECODE-FLOAT
 DECODE-UNIVERSAL-TIME DEFCLASS DEFCONSTANT DEFGENERIC DEFINE-COMPILER-MACRO
 DEFINE-CONDITION DEFINE-METHOD-COMBINATION DEFINE-MODIFY-MACRO
 DEFINE-SETF-EXPANDER DEFINE-SYMBOL-MACRO DEFMACRO DEFMETHOD DEFPACKAGE
 DEFPARAMETER DEFSETF DEFSTRUCT DEFTYPE DEFUN DEFVAR DELETE DELETE-DUPLICATES
 DELETE-FILE DELETE-IF DELETE-IF-NOT DELETE-PACKAGE DENOMINATOR DEPOSIT-FIELD
 DESCRIBE DESCRIBE-OBJECT DESTRUCTURING-BIND DIGIT-CHAR DIGIT-CHAR-P DIRECTORY
 DIRECTORY-NAMESTRING DISASSEMBLE DIVISION-BY-ZERO DO DO* DO-ALL-SYMBOLS
 DO-EXTERNAL-SYMBOLS DO-SYMBOLS DOCUMENTATION DOLIST DOTIMES DOUBLE-FLOAT
 DOUBLE-FLOAT-EPSILON DOUBLE-FLOAT-NEGATIVE-EPSILON DPB DRIBBLE DYNAMIC-EXTENT
 ECASE ECHO-STREAM ECHO-STREAM-INPUT-STREAM ECHO-STREAM-OUTPUT-STREAM ED EIGHTH
 ELT ENCODE-UNIVERSAL-TIME END-OF-FILE ENDP ENOUGH-NAMESTRING
 ENSURE-DIRECTORIES-EXIST ENSURE-GENERIC-FUNCTION EQ EQL EQUAL EQUALP ERROR
 ETYPECASE EVAL EVAL-WHEN EVENP EVERY EXP EXPORT EXPT EXTENDED-CHAR FBOUNDP
 FCEILING FDEFINITION FFLOOR FIFTH FILE-AUTHOR FILE-ERROR FILE-ERROR-PATHNAME
 FILE-LENGTH FILE-NAMESTRING FILE-POSITION FILE-STREAM FILE-STRING-LENGTH
 FILE-WRITE-DATE FILL FILL-POINTER FIND FIND-ALL-SYMBOLS FIND-CLASS FIND-IF
 FIND-IF-NOT FIND-METHOD FIND-PACKAGE FIND-RESTART FIND-SYMBOL FINISH-OUTPUT
 FIRST FIXNUM FLET FLOAT FLOAT-DIGITS FLOAT-PRECISION FLOAT-RADIX FLOAT-SIGN
 FLOATING-POINT-INEXACT FLOATING-POINT-INVALID-OPERATION
 FLOATING-POINT-OVERFLOW FLOATING-POINT-UNDERFLOW FLOATP FLOOR FMAKUNBOUND
 FORCE-OUTPUT FORMAT FORMATTER FOURTH FRESH-LINE FROUND FTRUNCATE FTYPE FUNCALL
 FUNCTION FUNCTION-KEYWORDS FUNCTION-LAMBDA-EXPRESSION FUNCTIONP GCD
 GENERIC-FUNCTION GENSYM GENTEMP GET GET-DECODED-TIME
 GET-DISPATCH-MACRO-CHARACTER GET-INTERNAL-REAL-TIME GET-INTERNAL-RUN-TIME
 GET-MACRO-CHARACTER GET-OUTPUT-STREAM-STRING GET-PROPERTIES GET-SETF-EXPANSION
 GET-UNIVERSAL-TIME GETF GETHASH GO GRAPHIC-CHAR-P HANDLER-BIND HANDLER-CASE
 HASH-TABLE HASH-TABLE-COUNT HASH-TABLE-P HASH-TABLE-REHASH-SIZE
 HASH-TABLE-REHASH-THRESHOLD HASH-TABLE-SIZE HASH-TABLE-TEST HOST-NAMESTRING
 IDENTITY IF IGNORABLE IGNORE IGNORE-ERRORS IMAGPART IMPORT IN-PACKAGE INCF
 INITIALIZE-INSTANCE INLINE INPUT-STREAM-P INSPECT INTEGER INTEGER-DECODE-FLOAT
 INTEGER-LENGTH INTEGERP INTERACTIVE-STREAM-P INTERN
 INTERNAL-TIME-UNITS-PER-SECOND INTERSECTION INVALID-METHOD-ERROR
 INVOKE-DEBUGGER INVOKE-RESTART INVOKE-RESTART-INTERACTIVELY ISQRT KEYWORD
 KEYWORDP LABELS LAMBDA LAMBDA-LIST-KEYWORDS LAMBDA-PARAMETERS-LIMIT LAST LCM
 LDB LDB-TEST LDIFF LEAST-NEGATIVE-DOUBLE-FLOAT LEAST-NEGATIVE-LONG-FLOAT
 LEAST-NEGATIVE-NORMALIZED-DOUBLE-FLOAT LEAST-NEGATIVE-NORMALIZED-LONG-FLOAT
 LEAST-NEGATIVE-NORMALIZED-SHORT-FLOAT LEAST-NEGATIVE-NORMALIZED-SINGLE-FLOAT
 LEAST-NEGATIVE-SHORT-FLOAT LEAST-NEGATIVE-SINGLE-FLOAT
 LEAST-POSITIVE-DOUBLE-FLOAT LEAST-POSITIVE-LONG-FLOAT
 LEAST-POSITIVE-NORMALIZED-DOUBLE-FLOAT LEAST-POSITIVE-NORMALIZED-LONG-FLOAT
 LEAST-POSITIVE-NORMALIZED-SHORT-FLOAT LEAST-POSITIVE-NORMALIZED-SINGLE-FLOAT
 LEAST-POSITIVE-SHORT-FLOAT LEAST-POSITIVE-SINGLE-FLOAT LENGTH LET LET*
 LISP-IMPLEMENTATION-TYPE LISP-IMPLEMENTATION-VERSION LIST LIST*
 LIST-ALL-PACKAGES LIST-LENGTH LISTEN LISTP LOAD
 LOAD-LOGICAL-PATHNAME-TRANSLATIONS LOAD-TIME-VALUE LOCALLY LOG LOGAND LOGANDC1
 LOGANDC2 LOGBITP LOGCOUNT LOGEQV LOGICAL-PATHNAME
 LOGICAL-PATHNAME-TRANSLATIONS LOGIOR LOGNAND LOGNOR LOGNOT LOGORC1 LOGORC2
 LOGTEST LOGXOR LONG-FLOAT LONG-FLOAT-EPSILON LONG-FLOAT-NEGATIVE-EPSILON
 LONG-SITE-NAME LOOP LOOP-FINISH LOWER-CASE-P MACHINE-INSTANCE MACHINE-TYPE
 MACHINE-VERSION MACRO-FUNCTION MACROEXPAND MACROEXPAND-1 MACROLET MAKE-ARRAY
 MAKE-BROADCAST-STREAM MAKE-CONCATENATED-STREAM MAKE-CONDITION
 MAKE-DISPATCH-MACRO-CHARACTER MAKE-ECHO-STREAM MAKE-HASH-TABLE MAKE-INSTANCE
 MAKE-INSTANCES-OBSOLETE MAKE-LIST MAKE-LOAD-FORM MAKE-LOAD-FORM-SAVING-SLOTS
 MAKE-METHOD MAKE-PACKAGE MAKE-PATHNAME MAKE-RANDOM-STATE MAKE-SEQUENCE
 MAKE-STRING MAKE-STRING-INPUT-STREAM MAKE-STRING-OUTPUT-STREAM MAKE-SYMBOL
 MAKE-SYNONYM-STREAM MAKE-TWO-WAY-STREAM MAKUNBOUND MAP MAP-INTO MAPC MAPCAN
 MAPCAR MAPCON MAPHASH MAPL MAPLIST MASK-FIELD MAX MEMBER MEMBER-IF
 MEMBER-IF-NOT MERGE MERGE-PATHNAMES METHOD METHOD-COMBINATION
 METHOD-COMBINATION-ERROR METHOD-QUALIFIERS MIN MINUSP MISMATCH MOD
 MOST-NEGATIVE-DOUBLE-FLOAT MOST-NEGATIVE-FIXNUM MOST-NEGATIVE-LONG-FLOAT
 MOST-NEGATIVE-SHORT-FLOAT MOST-NEGATIVE-SINGLE-FLOAT
 MOST-POSITIVE-DOUBLE-FLOAT MOST-POSITIVE-FIXNUM MOST-POSITIVE-LONG-FLOAT
 MOST-POSITIVE-SHORT-FLOAT MOST-POSITIVE-SINGLE-FLOAT MUFFLE-WARNING
 MULTIPLE-VALUE-BIND MULTIPLE-VALUE-CALL MULTIPLE-VALUE-LIST
 MULTIPLE-VALUE-PROG1 MULTIPLE-VALUE-SETQ MULTIPLE-VALUES-LIMIT NAME-CHAR
 NAMESTRING NBUTLAST NCONC NEXT-METHOD-P NIL NINTERSECTION NINTH
 NO-APPLICABLE-METHOD NO-NEXT-METHOD NOT NOTANY NOTEVERY NOTINLINE NRECONC
 NREVERSE NSET-DIFFERENCE NSET-EXCLUSIVE-OR NSTRING-CAPITALIZE NSTRING-DOWNCASE
 NSTRING-UPCASE NSUBLIS NSUBST NSUBST-IF NSUBST-IF-NOT NSUBSTITUTE
 NSUBSTITUTE-IF NSUBSTITUTE-IF-NOT NTH NTH-VALUE NTHCDR NULL NUMBER NUMBERP
 NUMERATOR NUNION ODDP OPEN OPEN-STREAM-P OPTIMIZE OR OTHERWISE OUTPUT-STREAM-P
 PACKAGE PACKAGE-ERROR PACKAGE-ERROR-PACKAGE PACKAGE-NAME PACKAGE-NICKNAMES
 PACKAGE-SHADOWING-SYMBOLS PACKAGE-USE-LIST PACKAGE-USED-BY-LIST PACKAGEP
 PAIRLIS PARSE-ERROR PARSE-INTEGER PARSE-NAMESTRING PATHNAME PATHNAME-DEVICE
 PATHNAME-DIRECTORY PATHNAME-HOST PATHNAME-MATCH-P PATHNAME-NAME PATHNAME-TYPE
 PATHNAME-VERSION PATHNAMEP PEEK-CHAR PHASE PI PLUSP POP POSITION POSITION-IF
 POSITION-IF-NOT PPRINT PPRINT-DISPATCH PPRINT-EXIT-IF-LIST-EXHAUSTED
 PPRINT-FILL PPRINT-INDENT PPRINT-LINEAR PPRINT-LOGICAL-BLOCK PPRINT-NEWLINE
 PPRINT-POP PPRINT-TAB PPRINT-TABULAR PRIN1 PRIN1-TO-STRING PRINC
 PRINC-TO-STRING PRINT PRINT-NOT-READABLE PRINT-NOT-READABLE-OBJECT
 PRINT-OBJECT PRINT-UNREADABLE-OBJECT PROBE-FILE PROCLAIM PROG PROG* PROG1
 PROG2 PROGN PROGRAM-ERROR PROGV PROVIDE PSETF PSETQ PUSH PUSHNEW QUOTE RANDOM
 RANDOM-STATE RANDOM-STATE-P RASSOC RASSOC-IF RASSOC-IF-NOT RATIO RATIONAL
 RATIONALIZE RATIONALP READ READ-BYTE READ-CHAR READ-CHAR-NO-HANG
 READ-DELIMITED-LIST READ-FROM-STRING READ-LINE READ-PRESERVING-WHITESPACE
 READ-SEQUENCE READER-ERROR READTABLE READTABLE-CASE READTABLEP REAL REALP
 REALPART REDUCE REINITIALIZE-INSTANCE REM REMF REMHASH REMOVE
 REMOVE-DUPLICATES REMOVE-IF REMOVE-IF-NOT REMOVE-METHOD REMPROP RENAME-FILE
 RENAME-PACKAGE REPLACE REQUIRE REST RESTART RESTART-BIND RESTART-CASE
 RESTART-NAME RETURN RETURN-FROM REVAPPEND REVERSE ROOM ROTATEF ROUND
 ROW-MAJOR-AREF RPLACA RPLACD SAFETY SATISFIES SBIT SCALE-FLOAT SCHAR SEARCH
 SECOND SEQUENCE SERIOUS-CONDITION SET SET-DIFFERENCE
 SET-DISPATCH-MACRO-CHARACTER SET-EXCLUSIVE-OR SET-MACRO-CHARACTER
 SET-PPRINT-DISPATCH SET-SYNTAX-FROM-CHAR SETF SETQ SEVENTH SHADOW
 SHADOWING-IMPORT SHARED-INITIALIZE SHIFTF SHORT-FLOAT SHORT-FLOAT-EPSILON
 SHORT-FLOAT-NEGATIVE-EPSILON SHORT-SITE-NAME SIGNAL SIGNED-BYTE SIGNUM
 SIMPLE-ARRAY SIMPLE-BASE-STRING SIMPLE-BIT-VECTOR SIMPLE-BIT-VECTOR-P
 SIMPLE-CONDITION SIMPLE-CONDITION-FORMAT-ARGUMENTS
 SIMPLE-CONDITION-FORMAT-CONTROL SIMPLE-ERROR SIMPLE-STRING SIMPLE-STRING-P
 SIMPLE-TYPE-ERROR SIMPLE-VECTOR SIMPLE-VECTOR-P SIMPLE-WARNING SIN
 SINGLE-FLOAT SINGLE-FLOAT-EPSILON SINGLE-FLOAT-NEGATIVE-EPSILON SINH SIXTH
 SLEEP SLOT-BOUNDP SLOT-EXISTS-P SLOT-MAKUNBOUND SLOT-MISSING SLOT-UNBOUND
 SLOT-VALUE SOFTWARE-TYPE SOFTWARE-VERSION SOME SORT SPACE SPECIAL
 SPECIAL-OPERATOR-P SPEED SQRT STABLE-SORT STANDARD STANDARD-CHAR
 STANDARD-CHAR-P STANDARD-CLASS STANDARD-GENERIC-FUNCTION STANDARD-METHOD
 STANDARD-OBJECT STEP STORAGE-CONDITION STORE-VALUE STREAM STREAM-ELEMENT-TYPE
 STREAM-ERROR STREAM-ERROR-STREAM STREAM-EXTERNAL-FORMAT STREAMP STRING
 STRING-CAPITALIZE STRING-DOWNCASE STRING-EQUAL STRING-GREATERP
 STRING-LEFT-TRIM STRING-LESSP STRING-NOT-EQUAL STRING-NOT-GREATERP
 STRING-NOT-LESSP STRING-RIGHT-TRIM STRING-STREAM STRING-TRIM STRING-UPCASE
 STRING/= STRING< STRING<= STRING= STRING> STRING>= STRINGP STRUCTURE
 STRUCTURE-CLASS STRUCTURE-OBJECT STYLE-WARNING SUBLIS SUBSEQ SUBSETP SUBST
 SUBST-IF SUBST-IF-NOT SUBSTITUTE SUBSTITUTE-IF SUBSTITUTE-IF-NOT SUBTYPEP
 SVREF SXHASH SYMBOL SYMBOL-FUNCTION SYMBOL-MACROLET SYMBOL-NAME SYMBOL-PACKAGE
 SYMBOL-PLIST SYMBOL-VALUE SYMBOLP SYNONYM-STREAM SYNONYM-STREAM-SYMBOL T
 TAGBODY TAILP TAN TANH TENTH TERPRI THE THIRD THROW TIME TRACE
 TRANSLATE-LOGICAL-PATHNAME TRANSLATE-PATHNAME TREE-EQUAL TRUENAME TRUNCATE
 TWO-WAY-STREAM TWO-WAY-STREAM-INPUT-STREAM TWO-WAY-STREAM-OUTPUT-STREAM TYPE
 TYPE-ERROR TYPE-ERROR-DATUM TYPE-ERROR-EXPECTED-TYPE TYPE-OF TYPECASE TYPEP
 UNBOUND-SLOT UNBOUND-SLOT-INSTANCE UNBOUND-VARIABLE UNDEFINED-FUNCTION
 UNEXPORT UNINTERN UNION UNLESS UNREAD-CHAR UNSIGNED-BYTE UNTRACE UNUSE-PACKAGE
 UNWIND-PROTECT UPDATE-INSTANCE-FOR-DIFFERENT-CLASS
 UPDATE-INSTANCE-FOR-REDEFINED-CLASS UPGRADED-ARRAY-ELEMENT-TYPE
 UPGRADED-COMPLEX-PART-TYPE UPPER-CASE-P USE-PACKAGE USE-VALUE
 USER-HOMEDIR-PATHNAME VALUES VALUES-LIST VARIABLE VECTOR VECTOR-POP
 VECTOR-PUSH VECTOR-PUSH-EXTEND VECTORP WARN WARNING WHEN WILD-PATHNAME-P
 WITH-ACCESSORS WITH-COMPILATION-UNIT WITH-CONDITION-RESTARTS
 WITH-HASH-TABLE-ITERATOR WITH-INPUT-FROM-STRING WITH-OPEN-FILE
 WITH-OPEN-STREAM WITH-OUTPUT-TO-STRING WITH-PACKAGE-ITERATOR
 WITH-SIMPLE-RESTART WITH-SLOTS WITH-STANDARD-IO-SYNTAX WRITE WRITE-BYTE
 WRITE-CHAR WRITE-LINE WRITE-SEQUENCE WRITE-STRING WRITE-TO-STRING Y-OR-N-P
 YES-OR-NO-P ZEROP
")

(setv all-cl-words  (all-cl-word.split) )
(setv cl-words
      (list
        (map
          (fn [x] (x.lower))
          (filter
            (fn [x]
              (setv y (re.match "[\w\-]+" x))
              (lif-not
                y False
                (if (in x ["-" "QUOTE"] )
                    False
                    True)))
            all-cl-words)  )))

(setv cl-custom-keywords
      [

       ;;"quote" "unquote" "quasiquote"
       "&rest"
       
       ;; "cons" "car" "cdr" "consp"
       ;; "eq" "eql" "equal"
       ;; "mod" "zerop" "plusp" "minusp" "oddp" "evenp" "divisible"
       ;; "length"  "emptyp"
       ;; "caar"    "cddr"       "cadr"       "cdar"
       ;; "nreverse"       "nconc"
       ;; "mapcan"       "mapcar"
       ;; "values"
       ;; "svref"
       
       ;; "let*"
       ;; "progn" "lambda" "identity"
       
       ;; "incf"  "decf"
       ;; "subseq"
       ;; "block"
       ;; "return-from"
       ;; "tagbody"
       ;; "go"
       ;; "symbol-macrolet"
       
       "ap:it"  "ap:alet"   "ap:slet"
       "ap:aand" "ap:sor"
       "ap:aif"  "ap:sif"
       "ap:awhen" "ap:swhen" "ap:sunless"
       "ap:acase" "ap:scase" "ap:scase"  "ap:aecase"   "ap:secase"  "ap:accase"  "ap:sccase"
       "ap:atypecase"  "ap:stypecase"  "ap:aetypecase"  "ap:setypecase"
       "ap:actypecase"  "ap:sctypecase"  "ap:acond"  "ap:scond"  "ap:aprog"
       "ap:ignore-first"
       
       "sb-c::check-ds-list"
       
       "macroexpand-dammit:macroexpand-dammit"

       "om:match" "om:guard" "ome:let-match"
       "tv:match"
       
       "alexandria:destructuring-case"
       ]
      )

(setv cl2hy-s-dic
      (dfor k cl-words
            [(hy.models.HySymbol (.upper k))
             (hy.models.HySymbol k)]))

(.update cl2hy-s-dic
         (dfor k cl-custom-keywords
            [(hy.models.HySymbol (.upper k))
             (hy.models.HySymbol k)]))


(setv hy2cl-s-dic
      (dfor k cl-words
            [
             (hy.models.HySymbol k)             
             (hy.models.HySymbol (.upper k))
             ]
            ))
(.update hy2cl-s-dic
         (dfor k cl-custom-keywords
               [
                (hy.models.HySymbol k)                
                (hy.models.HySymbol (.upper k))
                ]
               ))

(setv cl2hy-custom-s-dic
      {
       'nan numpy.nan
       'nil 'nil/cl
       'null 'null/cl
       't True
       'if 'if/cl
       'cond 'cond/cl
       'let 'let/cl
       'list   'list/cl 
       'vector 'vector/cl
       'the 'the/cl
       ;;', '~
       'progn  'do
       'locally 'do
       'first 'car
       'rest  'cdr
       'remove 'remove/cl
       'append 'append/cl
       'apply  'apply/cl
       'atom 'atom/cl
       'typep 'typep/cl
       'slot-value 'slot-value/cl       
       'multiple-value-bind 'multiple-value-bind/cl
       ;;'return-from 'return-from/cl
       ;;'block  'block/cl
       'error  'error/cl       
       'declare   'declare/cl
       'ignorable 'ignorable/cl
       'setf 'setv       
       ;;'setq 'setv
       'defvar 'setv
       'type  'dummy-fn/cl
       
       ;'QUOTE   'quote
       ;'UNQUOTE   'unquote
       ;'QUASIQUOTE   'quasiquote
       ;'UNQUOTE-SPLICE  'unquote-splice
       }
      )
(.update hy2cl-s-dic
         (dfor k cl2hy-custom-s-dic
               [
                (get cl2hy-custom-s-dic k)
                (hy.models.HySymbol (.upper (str k)))
                ]))

(.update cl2hy-s-dic
         (dfor k cl2hy-custom-s-dic
               [(hy.models.HySymbol (.upper (str k)))
                (get cl2hy-custom-s-dic k)]))

(.update cl2hy-s-dic
         (dfor k hy-repr-escape-words  
               [(hy.models.HySymbol (.upper k))
                (hy.models.HySymbol k) ]               ))


;; (setv
;;   cl2hy-s-dic
;;   (dfor (, k v) (cl2hy-s-dic.items)
;;         [(hy.models.HySymbol (.upper (str k))) v]))


(setv cl-keywords  ["else"]  )
(setv cl2hy-k-dic
      (dfor k cl-keywords
            [
             (hy.models.HyKeyword (.upper k))
             (hy.models.HyKeyword k)
             ]))
(setv hy2cl-k-dic
      (dfor k cl-keywords
            [
             (hy.models.HyKeyword k)
             (hy.models.HyKeyword (.upper k))             
             ]))

;; (for [(, k v) (cl2hy-s-dic.items)]
;;   (if (not (in v hy2cl-s-dic))
;;       (setv (get hy2cl-s-dic v)
;;             k)))
;; (for [(, k v) (hy2cl-s-dic.items)]
;;   (setv (get hy2cl-s-dic k) (hy.models.HySymbol (.upper (str v)))))

;; (setv cl-lowercase-keywords
;;       [
;;        ;;"quasiquote" "unquote"   "quote"
;;        "t"
;;        "let"  "let*"
;;        "list"
;;        "vector"
;;        "setq"  "setf"
;;        "assoc"

;;        "cons" "car" "cdr" "consp"
;;        "eq" "eql" "equal"
;;        "mod" "zerop" "plusp" "minusp" "oddp" "evenp" "divisible"
;;        "length"  "emptyp"
;;        "caar"    "cddr"       "cadr"       "cdar"
;;        "nreverse"       "nconc"
;;        "mapcan"       "mapcar"
;;        "values"
;;        "svref"

;;        "progn" "lambda" "identity"
       
;;        "incf"  "decf"
;;        "subseq"
;;        "block"
;;        "return-from"
;;        "tagbody"
;;        "go"
;;        "symbol-macrolet"
;;        ]
;; )
;
;; (.update hy2cl-s-dic
;;          (dfor k cl-lowercase-keywords
;;                [(hy.models.HySymbol k)
;;                 (hy.models.HySymbol (.upper k))  ]))



;; (defn q-element-rename [p &optional [cl2hy-s-dic cl2hy-s-dic]]
;;   ;;(print "q-element-cl-replace" p (isinstance p hyclb.core.ConsPair))
;;   (if (isinstance p hyclb.core.ConsPair)  p
;;       (if (symbol? p)
;;           (if (in p cl2hy-s-dic)
;;               (get cl2hy-s-dic p)
;;               ;;(hy.models.HySymbol  (.replace  (str p) ":" ".") )
;;               p
;;               )
;;           p)))

(defn cl2hy-symbol-deep [qexpr &optional [cl2hy-s-dic cl2hy-s-dic]];; &optional [clisp clisp]]
  ;;(print "q-exp-cl-rename-deep" (hy-repr p))
  (postwalk
    (fn [p]
      (if (isinstance p hyclb.core.ConsPair)  p
          (if (symbol? p)
              (if (in p cl2hy-s-dic)
                  (get cl2hy-s-dic p)
                  p)
              (if (and (keyword? p) (in p cl2hy-k-dic ))
                  (get cl2hy-k-dic p)
                  p))))
    qexpr)
  )

(defn hy2cl-symbol-deep [qexpr]
  (postwalk
    (fn [p]
      (if (and (symbol? p) (in p hy2cl-s-dic))
          (get hy2cl-s-dic p)
          (if (and (keyword? p) (in p hy2cl-k-dic))
              (get hy2cl-k-dic p)
              p) ))
    qexpr))


;; (defn from-pipe-symbol-str [st]
;;   (setv sts (st.split "|"))
;;   (.join
;;     ""
;;     (lfor (, k s) (enumerate sts)
;;           (if (and (= 1 (% k 2) ) (< k (- (len sts) 1)))
;;               s
;;               (.lower s)))))

;;(defn maybe-pipe-symbol-str [st] st)
(defn maybe-pipe-symbol-str [st &optional [escape False]]
  (if escape
      st
      st
      ;; (if
      ;;   (= st (.upper st))
      ;;   (.lower st)
      ;;   st)
      ))

(defn to-pipe-symbol [s &optional keywd]
  (setv st (str s))
  ;;(print st (.upper st) (= st (.upper st)) keywd)
  (if  (= st (.upper st))  ;;(= st (.lower st))
    s
    (do
      ;;(setv als (re.findall "[a-zA-Z]+" st))
      (setv als (re.findall "\w+" st))
      ;;(print als)
      (for [s als]
        (if (!= s (.upper s))  ;;(!= s (.lower s))
            (setv st (.replace st s (+ "|" s "|"))))
        ;;(print s st)
        )
      (lif-not keywd
           (hy.models.HySymbol  st)
           (hy.models.HyKeyword (cut st 1 None))
           ))))

;;(to-pipe-symbol 'aaa True)


(defn to-pipe-symbol-deep [qexpr]
  (postwalk
    (fn [p]
      (if (and (symbol? p) ( not (in p hy-repr-escape-symbols )))
          (to-pipe-symbol p)
          (if (keyword? p)
              (to-pipe-symbol p True)
              p)))
    qexpr))
  



(defn left_parenthesis  [r s c]
  (r.read_delimited_list ")" s True)
  ;;(list/cl  #*(r.read_delimited_list ")" s True))
  ;; (setv ret (r.read_delimited_list ")" s True))
  ;; (print "left_parenthesis ret" ret)
  ;; ret
  ;;(+ '(list) (r.read_delimited_list ")" s True))
  )

(defn right_parenthesis [r s c] (raise (RuntimeError "Unmatched closing parenthesis.")))

(defn single_quote [r s c] (quote (r.read_aux s) )) 
(defn sharpsign_equal [r s c n]
  (setv value  (r.read_aux s))
  (SharpsignEquals n value))
(defn sharpsign_sharpsign [r s c n] (SharpsignSharpsign n))

(defn sharpsign_left_parenthesis [r s c n]
  (setv l  (r.read_delimited_list ")"  s True))
  ;;(if (not l) [] (list l))
  (if (not l) (vector/cl ) (vector/cl  #*(list l)))
  ;;(if (not l) '() (+ '(vector) l))
  )

;;;;not compat 
;; (defn sharpsign_left_parenthesis [r s c n]
;;   (setv l  (r.read_delimited_list ")",s, True))
;;   (if (not l)
;;       (numpy.array []) ;; '()
;;       (numpy.array l)))

(defn sharpsign_m [r s c n]
  (setv data  (r.read_aux s))
  ;;(print "sharpsign_m" data)
  (setv name   (hyclb.core.car data)
        alist  (hyclb.core.cdr data)
        spec   (importlib.machinery.ModuleSpec name None)
        module (importlib.util.module_from_spec spec)
        module.__class__  Package)
  ;;(print module)
  ;;# Now register all exported functions.
  (for [cons1  alist]
    ;;(print cons1)
    (setv car1 (hyclb.core.car cons1))
    (if (symbol? car1)
        (setattr module  (str car1) (hyclb.core.cdr cons1)  )
        (if (hasattr car1 "python_name")
            (setattr module (. car1 python_name) (hyclb.core.cdr cons1) ) )))
  ;;(print module)
  module)

(defn sharpsign_colon [r s c n]   ;;gensym var
  (setv data (r.read_aux s))
  ;;(print "sharpsign_colon" data)
  (hy.models.HySymbol
    ;;(.lower
      (+ "_G" data)
      ;;)
    ))

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
  ;;(print "sharpsign ret" c n r s)
  ((r.get_dispatch_macro_character "#" c) r s c n))


(defclass ReadtableHy [cl4py.reader.Readtable]
  (defn __init__ [self lisp]
    (.__init__ (super) lisp)
    (self.set_macro_character "(" left_parenthesis)
    (self.set_macro_character ")" right_parenthesis)
    (self.set_macro_character "'" single_quote)
    (self.set_macro_character "#" sharpsign)
    (self.set_dispatch_macro_character "#" "(" sharpsign_left_parenthesis)
    (self.set_dispatch_macro_character "#" "M" sharpsign_m)
    (self.set_dispatch_macro_character "#" "=" sharpsign_equal)
    (self.set_dispatch_macro_character "#" "#" sharpsign_sharpsign)
    (self.set_dispatch_macro_character "#" ":" sharpsign_colon)
    )

  (defn read [self stream &optional [recursive False]]
    (if (not (isinstance stream Stream))
             (setv stream  (Stream stream :debug self.lisp.debug)))
    (setv value  (self.read_aux stream))
    ;;(print "read ret val" value (type value))
    (setv ret  (if recursive value (circularize value)))
    ;;(print "read ret" ret (type ret))
    (setv ret2 (cl2hy-symbol-deep ret)) 
    ;;(print "read ret2" ret2 (type ret2))
    ret2
    )

  (defn read_str [self s &optional [recursive False]]
    (import [io [StringIO]])
    (self.read (StringIO s) recursive))
  
  (defn reads [self stream &optional [recursive False]]
    (if (not (isinstance stream cl4py.data.Stream))
        (setv stream  (Stream stream :debug self.lisp.debug)))
    (setv sexps [])
    (while True
      (try 
        (.append sexps (self.read stream recursive))
        ;;(print (hy-repr sexps ))
        (except [e [ EOFError ]]
          (break)) )
      )
    sexps)

  (defn loadsexps [self fpath]
    (with [f (open fpath)]
      (self.reads f)))
  
  (defn read_aux [self stream &optional [casesensitive False]]
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
           ;;(print "get_macro_character ret" x  value)
           (lif-not value (continue) (return value)))]
        ;;# 5. single escape character
        [(= syntax_type cl4py.reader.SyntaxType.SINGLE_ESCAPE)
         (setv token [(stream.read_char)]  escape False)]
        ;;# 6. multiple escape character
        [(= syntax_type cl4py.reader.SyntaxType.MULTIPLE_ESCAPE)
         (setv token  []                escape  True   casesensitive True)]
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
      
      ;;(print "last token:" (.join "" token) casesensitive escape)
      
      ;;# 10.
      ;; (setv ret (self.parse (.join "" token)))
      ;; (print "ret" ret)
      ;; (return ret)
      (return (self.parse (.join "" token) casesensitive))
      ;;(return (.join "" token)))
      ))

  (defn parse [self token &optional [casesensitive False] ]
    ;;(print "parse" token casesensitive)
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
          ;;(if (= (.upper name) "T"  ) (return True))
          ;;(if (= (.upper name) "NIL") (return '()))
          
          ;; (if (in (.upper package) ["CL" "COMMON-LISP"])
          ;;     (return (hy.models.HySymbol name)))
          ;; (if package
          ;;     (if delimiter                (if delimiter
          ;; (return (hy.models.HySymbol (+ package "::" name))))))
          (if (not package)
              (if delimiter
                  (return (hy.models.HyKeyword
                            (maybe-pipe-symbol-str name casesensitive)
                            ;;(lif casesensitive name (.lower name))
                            ))
                  (return (hy.models.HySymbol
                            (maybe-pipe-symbol-str name casesensitive)
                            ;;(lif casesensitive name (.lower name))
                            )))
              ;;(return (hy.models.HySymbol (+ name ":" self.lisp.package)))
              (if (in (.upper package)
                      ["CL" "COMMON-LISP" "CL4PY" ]
                                ;["CL" "COMMON-LISP" ]                        
                      )
                  (return (hy.models.HySymbol
                            (maybe-pipe-symbol-str name casesensitive)
                            ;;(lif casesensitive name (.lower name))
                            ))
                  (return (hy.models.HySymbol
                            (maybe-pipe-symbol-str (+ package delimiter name) casesensitive)
                            ;; (lif casesensitive (+ package delimiter name) (.lower (+ package delimiter name)
                            ;;                                                       ;;(+ package "::" name)
                            ;;                                                       ;; (.replace 
                            ;;                                                       ;;   (+ package "." name)
                            ;;                                                       ;;   ":" ".")
                            ;;                                                       ))
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
      ;;(print "tail_add-top" head delim)
      (skip_whitespace)
      (setv x (stream.read_char))
      (cond
        [(= x  delim)
         (do
           ;;(print "head-ret" (hy-repr head))
           ;;(print "head-ret" head)
           head
           )
           ]
        [(= x ".")
         (do
           (setv e (self.read stream True))
           ;;(setv head (hyclb.core.cons head e))
           ;;(tail_add head delim)
           ;;(tail_add (hyclb.core.cons head e) delim)
           (if (empty? (cut head None -1))
               (tail_add
                 (hyclb.core.cons
                   (last head)
                   e)
                 delim)
               (tail_add
                 (hyclb.core.cons #*(+ head `(~e)))
                 delim))
           ;;(tail_add (cons head e) delim)
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
    ;;(tail_add (,) delim)
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
    ;;(setv val (self.readtable.read self.stdout :recursive True))
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
    (print msg :end "")
    ;;# If there is an error, raise it.
    ;; if isinstance(err, Cons):
    (if (coll? err)
        (do
          (print "err" (hy-repr err))
          ;; (setv condition (hyclb.core.car err)
          ;;       msg
          ;;       (if (hyclb.core.null/cl (hyclb.core.cdr err))
          ;;           "" (hyclb.core.car (hyclb.core.cdr err))))
          ;; (defn init [self] (RuntimeError.__init__  self msg))
          ;; (raise ((type (str condition) (, RuntimeError), {"__init__" init})))
          )
        )

    
    ;; ;; # Now, check whether there are any unpatched instances.  If so,
    ;; ;;  # figure out their class definitions and patch them accordingly.
    ;; (setv items  (list (self.unpatched_instances.items)))
    ;; (self.unpatched_instances.clear)
    ;; (for [(, cls_name instances) items]
    ;;   (print "cls_name" cls_name)
    ;;   (print "instances" instances)      
    ;;   (setv
    ;;     cls (type cls_name.python_name (, LispWrapper) {})
    ;;     (get self.classes cls_name) cls
    ;;     alist  ((self.function "cl4py:class-information") cls_name))
    ;;   (for [cons alist]
    ;;     (add_member_function cls (car cons) (cdr cons)))
    ;;   (for [instance instances]
    ;;     (setv instance.__class__  cls)))

    
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
    ;; ;;(print (hy-repr qexpr))
    ;; (setv qexpr (hy2cl-symbol-deep  qexpr))
    ;; ;;(print (hy-repr qexpr))    
    ;; (setv qexpr (to-pipe-symbol-deep qexpr))
    ;; ;;(print (hy-repr qexpr))
    (setv exs (cut (hy-repr qexpr) 1 None))
    ;;(print exs)
    (self.eval_str exs) )
  )

(setv clisp (Clisp :quicklisp True))





;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;pre load packages

(clisp.eval_str "(ql:quickload \"alexandria\")")
;;(clisp.eval_str "(rename-package 'alexandria 'alex))
;;(clisp.eval_str "(sb-ext:unlock-package 'alexandria))

(clisp.eval_str "(ql:quickload \"macroexpand-dammit\")")

(clisp.eval_str "(ql:quickload \"anaphora\")")

(clisp.eval_str "(ql:quickload \"optima\")")


;;(clisp.eval_str "(ql:quickload \"iterate\")" )

;;(clisp.eval_str "(ql:quickload \"trivia\")")

(clisp.eval_str "(ql:quickload \"sxql\")")
(clisp.eval_str "(ql:quickload \"jsown\")")
(clisp.eval_str "(ql:quickload \"unix-opts\")")

(clisp.eval_str "(ql:quickload \"fare-quasiquote\")")
(clisp.eval_str "(asdf:load-system \"fare-quasiquote-extras\")")
(clisp.eval_str "(named-readtables:in-readtable :fare-quasiquote)")

(clisp.eval_str "(rename-package 'anaphora 'ap)")
;;(clisp.eval_str "(add-nickname :ap :anaphora))

(clisp.eval_str "(rename-package 'optima 'om)")
(clisp.eval_str "(rename-package 'optima.core 'omc)")
(clisp.eval_str "(rename-package 'optima.extra 'ome)")

;; (clisp.eval_str "(rename-package 'trivia 'tv)")
;; (clisp.eval_str "(rename-package 'trivia.level1 'tv1)")
;; (clisp.eval_str "(rename-package 'trivia.level1.impl 'tv1i)")
;; (clisp.eval_str "(rename-package 'trivia.skip 'tvskip)")
;;(clisp.eval_str "(rename-package 'trivia.balland2006 'tvballand2006")  ;;;error 



;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (defmacro SB-KERNEL:%RPLACD [&rest args]
;;   `(rplacd ~@args))

(defn OMC:%ASSOC [item alist &optional [test hyclb.core.eql]]
  ;;"Safe ASSOC."
  ;;(declare (optimize (speed 3) (safety 0) (space 0)))
  ;; (loop
  ;;   (unless (consp alist) (return))
  ;;   (let ((cons (car alist)))
  ;;     (when (and (consp cons)
  ;;                (funcall test item (car cons)))
  ;;       (return cons)))
  ;;   (setq alist (cdr alist))))
  (hyclb.core.cons item (get alist item))
  )

(defn OMC:%EQUAL [a b] (= a b))

(defn OMC:%SVREF [simple-vector index]  (get simple-vector index))

(defn OMC:%GET-PROPERTY [item plist]
  (if (in item plist)
      (do
        (setv i (.index plist item))
        (cut plist (+ 1 i) None))
      nil/cl))

;;(clisp.eval_qexpr `(defstruct numpy.ndarray  shape ndim))

(defn cl_struct_import_obj [obj]
  (setv classname  (. (type obj) __name__))
  (setv modulename (. (type obj) __module__))
  (setv propnames (dir obj) )
  (setv clstr (+ "(defstruct |" modulename "." classname "| "
                 (.join " "  (map (fn [x] (+ "|" x "|"))  propnames )
                            ) " )" ))
  ;;(print clstr)
  (clisp.eval_str clstr)
  )

(cl_struct_import_obj (numpy.array [1 2 3 ]))



(defn cl_eval_str  [expr] (clisp.eval_str expr))
(defn cl_eval_qexpr [expr] (clisp.eval_qexpr expr))

(defn cl_eval_hy_qexpr [qexpr]
  ;(print (hy-repr qexpr))
  (setv qexpr (hy2cl-symbol-deep  qexpr))
  ;(print (hy-repr qexpr))    
  (setv qexpr (to-pipe-symbol-deep qexpr))
  ;(print (hy-repr qexpr))
  (clisp.eval_qexpr qexpr)
  )

;;(setv hy2cl-s-dic-str (dfor (, k v) (hy2cl-s-dic.items) [(str k) (str v)]))

;; (defn cl_eval_hy_str [expr]
;;   (for [(, k v) (hy2cl-s-dic-str.items)]
;;     (setv expr (.replace expr k v )))
;;   (clisp.eval_str expr))



(defmacro cl_eval_hy [expr]
  (setv ret (cl_eval_hy_qexpr expr))
  `'~ret
  )



;; (clisp.eval_qexpr
;;   '(defmacro expandmacro-with-env (form &environment env)
;;      (multiple-value-bind (expansion expanded-p)
;;                           (macroexpand form env)
;;                           `(values ',expansion ',expanded-p)))
;;   )
;; (clisp.eval_qexpr
;;   '(defmacro expandmacro1-with-env (form &environment env)
;;      (multiple-value-bind (expansion expanded-p)
;;                           (macroexpand-1 form env)
;;                           `(values ',expansion ',expanded-p)))
;;   )

;; (defn qexp-macroexpand-env-sents
;;   [p &optional  [env-sents []] ]
;;   (setv p1 `(expandmacro-with-env ~p))
;;   (for [s (nreverse env-sents)]
;;     (setv p1 (+ s `(~p1)))
;;     )
;;   p1
;;   )

;; (hy-repr
;; (qexp-macroexpand-env-sents
;;   '(print 12)
;;   '(
;;     (let  ((a 12)))
;;      (let* ((b 22)))
;;      ))
;; )
;; "'(let ((a 12)) (let* ((b 22)) (expandmacro-with-env (print 12))))"


;; (defn qexp-macroexpand-1-with-env
;;   [p &optional
;;    [symbol-macrolet-var-paris []]
;;    [macrolet-var-paris []]
;;    ;;[flet-var-paris []]
;;    ]
;;   (setv p1 `(expandmacro-with-env ~p))
;;   (if (not (empty? macrolet-var-paris))
;;       (setv p1 `(macrolet ~macrolet-var-paris ~p1)))
;;   (if (not (empty? symbol-macrolet-var-paris))
;;       (setv p1 `(symbol-macrolet-var-paris ~symbol-macrolet-var-paris ~p1)))
;;   (setv p2 (clisp.eval_qexpr p1))
;;   p2
;;   )





;;(setv non-cl-macro-expand-symbols [])
(setv non-cl-macro-expand-symbols
      [
       ;;'om:fail 'om::fail
       ;;'om:%fail 'om::%fail 'om:fail
       ])
(+= non-cl-macro-expand-symbols
    (lfor k non-cl-macro-expand-symbols (hy.models.HySymbol (.upper (str k)))))


(defn non-cl-macro-expand-expr? [p &optional [non-cl-macro-expand-symbols non-cl-macro-expand-symbols] ]
  (for [f non-cl-macro-expand-symbols]
    ;;(print (hy-repr p))
    (if (q-exp-fn0? p f)
        (return True)))
  False)


;; (defn qexp-macroexpand-with-fail [p]
;;   (lif p2
;;        (if (and (coll? p2) (empty? p2 ))
;;                (walk (fn [p] (inner p smaclet-vpar)) identity p)
;;                (walk (fn [p2] (inner p2 smaclet-vpar)) identity p2)
;;                )
;;            (walk (fn [p] (inner p smaclet-vpar)) identity p)
;;            ))
    

(defn qexp-macroexpand-1 [p &optional [non-cl-macro-expand-symbols non-cl-macro-expand-symbols] ]
  (if (non-cl-macro-expand-expr? p non-cl-macro-expand-symbols)
      p
      (do
        ;;(print "mex1fn")
        ;; (print (hy-repr non-cl-macro-expand-symbols))        
        ;;(print (hy-repr p))        
        (setv p3 (cl_eval_hy_qexpr `(MACROEXPAND-1 '~p))) ;
        ;;(print (hy-repr p3))
        p3
        )))
  
(import copy)

(defn q-exp-macroexpand-flag [p2]
  (lif p2
       (if (and (coll? p2) (empty? p2 ))
           True
           False)
       True))

(defn qexp-macroexpand-2 [p &optional [non-cl-macro-expand-symbols non-cl-macro-expand-symbols] ]
  (setv change-flag True)
  (while change-flag
    (setv p-pre (copy.copy p))
    (setv p (qexp-macroexpand-1 p non-cl-macro-expand-symbols))
    (setv change-flag (not (= p-pre p)))
    (if (q-exp-macroexpand-flag p)  (return p-pre)))
  p)
  

(defn q-exp-clmc-rename-deep4 [p &optional [non-cl-macro-expand-symbols non-cl-macro-expand-symbols] ]
  (cl_eval_hy_qexpr `(MACROEXPAND-DAMMIT:MACROEXPAND-DAMMIT '~p)))
  


;; (defmacro labels [name arg &rest code]
;;   `(defn ~name [~@arg]
;;      ~@(lfor p code (q-exp-cl-rename-deep p)))
;;      )

(defmacro defun [name arg &rest code]
  ;;(print "defun" name)
  `(defn ~name [~@arg]
     ~@(lfor p code
             (do
               ;;(print "p0" (hy-repr p))
               ;;(setv p (hy2cl-symbol-deep p))
               ;;(print "p1" (hy-repr p))
               ;;(print "ex1" (hy-repr (clisp.eval_qexpr `(MACROEXPAND-DAMMIT:MACROEXPAND-DAMMIT '~p))))
               (setv ret1 (q-exp-clmc-rename-deep4 p) )
               ;;(print "ret1" (hy-repr ret1))
               (setv ret2 (cl2hy-symbol-deep ret1))
               ;;(print "ret2" (hy-repr ret2))
               ret2
               ))))


(defmacro defun/global [name arg &rest code]
  `(do
     (global ~name)
     (defun ~name ~arg ~@code)
     )
  )


;; (defmacro defmacro/cl [&rest args]
;;   `(defmacro ~args) 
;;   )

;; (defmacro progn-helper [body]  `(do ~@body))

;; (defn load/cl [fpath]
;;   (with [f (open fpath)]
;;     (for [p (clisp.readtable.reads f)]
;;       (print (hy-repr p))
;;       (print (eval p))
;;       )
;;   ))

(setv renames-when-load
      {
       ;;'defmacro 'defmacro/cl
       'defun 'defun/global
       }
      )


(defmacro load/cl [filepath]
  ;;(print "load/cl" filepath)
  ;; (setv codes (clisp.readtable.loadsexps `~filepath))
  ;; (print codes)
  ;; codes
  ;;(setv codes (for [p (clisp.readtable.loadsexps `~filepath)]  eval p)) )
  ;; (print (hy-repr codes))  codes
  
  ;;`(for [p (clisp.readtable.loadsexps ~filepath)] (eval p))
  
  `(for [p (clisp.readtable.loadsexps ~filepath)]
     (eval
       (do
         (setv qp (cl2hy-symbol-deep p renames-when-load) )
         ;;(print (hy-repr qp))
         qp
           )  ))

  ;;`(progn-helper ~`(clisp.readtable.loadsexps ~filepath))
  ;;`(clisp.readtable.loadsexps ~filepath)
  )


