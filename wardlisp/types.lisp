;;;; wardlisp/types.lisp --- Value types for the WardLisp language.
;;;;
;;;; WardLisp values are represented using CL objects:
;;;; - Numbers: CL integer/rational
;;;; - Booleans: :true / :false (distinct from CL T/NIL)
;;;; - Symbols: CL keywords (:up, :down, etc.)
;;;; - Lists: CL cons cells terminated by :wnil
;;;; - Nil: :wnil (empty list)
;;;; - Closures: struct with params, body, env

(defpackage #:recurya/wardlisp/types
  (:use #:cl)
  (:export #:wardlisp-true
           #:wardlisp-false
           #:wardlisp-nil
           #:wardlisp-number-p
           #:wardlisp-boolean-p
           #:wardlisp-symbol-p
           #:wardlisp-list-p
           #:wardlisp-nil-p
           #:wardlisp-closure-p
           #:wardlisp-self-evaluating-p
           #:make-closure
           #:closure-params
           #:closure-body
           #:closure-env
           #:wardlisp-equal
           #:wardlisp->string
           #:wardlisp-truthy-p))

(in-package #:recurya/wardlisp/types)

;;; --- Constants ---

(defconstant wardlisp-true :true
  "WardLisp boolean true value.")

(defconstant wardlisp-false :false
  "WardLisp boolean false value.")

(defconstant wardlisp-nil :wnil
  "WardLisp nil / empty list value.")

;;; --- Closures ---

(defstruct (closure (:constructor %make-closure))
  "A WardLisp closure capturing lexical environment."
  (params nil :type list)
  (body nil :type list)
  (env nil))

(defun make-closure (params body env)
  "Create a WardLisp closure."
  (%make-closure :params params :body body :env env))

(defun wardlisp-closure-p (val)
  "Return T if VAL is a WardLisp closure."
  (closure-p val))

;;; --- Type Predicates ---

(defun wardlisp-number-p (val)
  "Return T if VAL is a WardLisp number."
  (numberp val))

(defun wardlisp-boolean-p (val)
  "Return T if VAL is a WardLisp boolean."
  (or (eq val wardlisp-true) (eq val wardlisp-false)))

(defun wardlisp-symbol-p (val)
  "Return T if VAL is a WardLisp symbol (keyword, not boolean/nil)."
  (and (keywordp val)
       (not (wardlisp-boolean-p val))
       (not (eq val wardlisp-nil))))

(defun wardlisp-nil-p (val)
  "Return T if VAL is WardLisp nil."
  (eq val wardlisp-nil))

(defun wardlisp-list-p (val)
  "Return T if VAL is a WardLisp list (cons cell or nil)."
  (or (wardlisp-nil-p val) (consp val)))

(defun wardlisp-self-evaluating-p (val)
  "Return T if VAL is self-evaluating (number, boolean, keyword)."
  (or (wardlisp-number-p val)
      (wardlisp-boolean-p val)
      (wardlisp-symbol-p val)))

(defun wardlisp-truthy-p (val)
  "Return T if VAL is truthy in WardLisp. Only #f is falsy."
  (not (eq val wardlisp-false)))

;;; --- Equality ---

(defun wardlisp-equal (a b)
  "Deep equality comparison for WardLisp values."
  (cond
    ((and (wardlisp-nil-p a) (wardlisp-nil-p b)) t)
    ((and (numberp a) (numberp b)) (= a b))
    ((and (keywordp a) (keywordp b)) (eq a b))
    ((and (consp a) (consp b))
     (and (wardlisp-equal (car a) (car b))
          (wardlisp-equal (cdr a) (cdr b))))
    ((and (closure-p a) (closure-p b)) (eq a b))
    (t nil)))

;;; --- Display ---

(defun wardlisp->string (val)
  "Convert a WardLisp value to its display string."
  (cond
    ((eq val wardlisp-true) "#t")
    ((eq val wardlisp-false) "#f")
    ((wardlisp-nil-p val) "()")
    ((numberp val) (format nil "~A" val))
    ((keywordp val) (format nil ":~(~A~)" val))
    ((consp val) (format nil "(~A)" (list-contents->string val)))
    ((closure-p val) "#<closure>")
    (t (format nil "~A" val))))

(defun list-contents->string (val)
  "Convert list contents to display string (without outer parens)."
  (cond
    ((wardlisp-nil-p val) "")
    ((not (consp (cdr val)))
     (if (wardlisp-nil-p (cdr val))
         (wardlisp->string (car val))
         (format nil "~A . ~A" (wardlisp->string (car val))
                 (wardlisp->string (cdr val)))))
    (t (format nil "~A ~A" (wardlisp->string (car val))
               (list-contents->string (cdr val))))))
