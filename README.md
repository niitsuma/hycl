hyclb
========

[![Build Status](https://img.shields.io/travis/niitsuma/hycl/master.svg?style=flat-square)](https://travis-ci.org/niitsuma/hycl)
[![Downloads](https://img.shields.io/pypi/dm/hyclb.svg?style=flat-square)](https://pypi.python.org/pypi/hyclb)
[![Version](https://img.shields.io/pypi/v/hyclb.svg?style=flat-square)](https://pypi.python.org/pypi/hyclb)

common-lisp-like functions and macros for hylang


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

(setv clisp (Clisp :quicklisp True))
(clisp.eval_qexpr  '(ql:quickload "alexandria"))
(clisp.eval_str  "(alexandria:destructuring-case '(:x 0 1 2)   ((:x x y z) (list x y z))  ((t &rest rest) :else))")
==> [0 1 2]


(require  [hyclb.cl4hy [*]])

(import numpy) 
(defun testfn3 (X Y)
  (numpy.random.rand
    (get 
      (alexandria:destructuring-case
        '(:a 0 X Y)   ((:a u v w) (list 1 2 u v w ))  ((t &rest rest) :else))
      0)
    )
  )
(print (testfn3 3 2))
==> [0.51005462]

```


More examples can be found in the test
