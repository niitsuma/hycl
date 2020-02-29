hyclb
========

[![Build Status](https://img.shields.io/travis/niitsuma/hycl/master.svg?style=flat-square)](https://travis-ci.org/niitsuma/hycl)
[![Downloads](https://pepy.tech/badge/hyclb)](https://pepy.tech/project/hyclb)
[![Version](https://img.shields.io/pypi/v/hyclb.svg?style=flat-square)](https://pypi.python.org/pypi/hyclb)

common-lisp interface and common-lisp-like functions for hylang

Installation
------------

```shell
$ pip install hyclb
```

Example
-------
```hy
(import   [hyclb.core [*]])
(require  [hyclb.core [*]])

(if/cl nil/cl True ) 
==> []


(dbind
 (a (b c) d) 
 (1 (2 3) 4)
 [a b c d])
 
==> [1 2 3 4]


(import   [hyclb.util [*]])
(require  [hyclb.util [*]])

(defun testfn2 (x y)
   (setq z 20)
   (if x (+ z y)))
   
(testfn2 [] 2)
==>  []


(import  [hyclb.cl4hy [*]])
(require  [hyclb.cl4hy [*]])

(setv clisp (Clisp :quicklisp True))

(clisp.eval_qexpr '(+ 2 5))
==> 7

;;(clisp.eval_qexpr  '(ql:quickload "alexandria")) ;;alexandria pre-loaded inside hyclb
(clisp.eval_str  "(alexandria:destructuring-case '(:x 0 1 2)   ((:x x y z) (list x y z))  ((t &rest rest) :else))")
==>'(0 1 2)


;(clisp.eval_qexpr '(ql:quickload "anaphora"))       ;;anaphora pre-loaded inside hyclb
;(clisp.eval_qexpr '(rename-package 'anaphora 'ap) ) ;;anaphora renamed inside hyclb

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

;(clisp.eval_qexpr '(ql:quickload "optima"))                ;;optima  pre-loaded inside hyclb
;(clisp.eval_qexpr '(rename-package 'optima 'om) )          ;;optima  renamed inside hyclb
;(clisp.eval_qexpr '(rename-package 'optima.core 'omc) )    ;;optima.core  renamed inside hyclb to avoid using  python namespace "optima.*"
(defun testfn []
    (om:match (list 1 2)
              ((list _) 1)
              ((list _ _) 2)
              ((list _ _ _) 3)
              ) )

(testfn)
==>  2

```


More examples can be found in the test
