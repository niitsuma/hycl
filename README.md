# hyclb

[![Build Status](https://img.shields.io/travis/niitsuma/hycl/master.svg?style=flat-square)](https://travis-ci.org/niitsuma/hycl)
[![Downloads](https://pepy.tech/badge/hyclb)](https://pepy.tech/project/hyclb)
[![Version](https://img.shields.io/pypi/v/hyclb.svg?style=flat-square)](https://pypi.python.org/pypi/hyclb)

common-lisp interface and common-lisp-like functions for hylang

## Installation

```shell
$ pip install hyclb
```

## Usage
### basic usage
```hy
(import   [hyclb.core [*]])
(require  [hyclb.core [*]])
(import   [hyclb.cl4hy [*]])
(require  [hyclb.cl4hy [*]])


(setv clisp (Clisp :quicklisp True))

(clisp.eval_str "(lisp-implementation-type)" )
==> 'SBCL'

(clisp.eval_str   "(+ 2 5)")
(clisp.eval_qexpr '(+ 2 5))
(cl_eval_str      "(+ 2 5)")  ;alias
(cl_eval_qexpr    '(+ 2 5))   ;alias
==> 7
```

### defun macro

`defun` macro is hy-lang macro mimiking common-lisp as
```hy
(defmacro defun [name arg &rest code]
 `(defn ~name [~@arg]
   macroexpand-all "code" in SBCL : (clisp.eval_qexpr `(macroexpand-all ~code)) 
   the expanded "code" executed using cl-compat functions on hy. 
  ))
```

defun macro usage

```hy

;(clisp.eval_qexpr '(ql:quickload "optima"))                ;optima  pre-loaded inside hyclb
;(clisp.eval_qexpr '(rename-package 'optima 'om) )          ;optima  renamed inside hyclb
;(clisp.eval_qexpr '(rename-package 'optima.core 'omc) )    ;optima.core  renamed inside hyclb to avoid using python namespace "optima.*"

(import numpy)
(defun testom4 (u)
    (setq p numpy.pi)
    (om:match
      u
      (`(,x 5 ,z)  (list x y z))
      (`(,x ,p ,z) (list x 2 z)))
    )
	
(testom4 (list/cl  1 numpy.pi  3) )	
==> '(1 2 3)


;(clisp.eval_qexpr `(defstruct numpy.ndarray  shape ndim)) ;numpy.ndarray pre-import to cl inside hyclb
;(cl_struct_import_obj (numpy.array [1 2 3 ]))             ;import uitlity 
(defun testom6 (z)
    (om:match
      z
      ((numpy.ndarray shape ndim ) (list shape ndim )))
    )

(testom6 (numpy.array [1 2 3]))
==>    '( (, 3) 1)

```

### cl-compat hy functions in hyclb.core 

many cl-compat hy functions are implemented  in hyclb.core.
plz see `tests/test_core.h`
Some cl-compat hy function names which conflict with python names are renamed `foo/cl`

```hy
(progn (print 111))
(mapcan (fn [x] [(+ x 10) "x"]) [1 2 3 4])
...

(list/cl 1 2 3)  ;/cl use for avoiding conflict python list 
==> '(1 2 3)

(vector/cl 1 2 3)
==> [1 2 3]

(hy-repr (vector/cl 1 2 3)
==> "#(1 2 3)" ; hy-repr output cl like sexp
```


### Naming rule

Some function deals None as nil.

```hy
(assoc/cl  'x {'x 10 'y 20})
==> (cons 'x 10)

(assoc/cl  'z {'x 10 'y 20})
==>  nil/cl

(assoc/clp 'z {'x 10 'y 20}) ;/clp => None = nil
None
```


### Other examples

```hy
(dbind
 (a (b c) d) 
 (1 (2 3) 4)
 [a b c d])
 
==> [1 2 3 4]

;(clisp.eval_qexpr '(ql:quickload "anaphora"))       ;anaphora pre-loaded inside hyclb
;(clisp.eval_qexpr '(rename-package 'anaphora 'ap) ) ;anaphora renamed inside hyclb

(import numpy) 
(defun test_alet2 (x y)
  (setq y (+ 10 y))
  (numpy.sin
    (* 
      (ap:alet (+ x y)  (+ 1 ap:it))
      (/ numpy.pi 180)))
  )
  
(test_alet2 49 30)
==> 1.0	


(load/cl "tests/simple.lisp")
(testfn 3 4)
==>    15

```


More examples can be found in the tests directory

