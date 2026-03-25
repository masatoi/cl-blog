;;;; wardlisp/environment.lisp --- Lexical environment for WardLisp.
;;;;
;;;; Environments are represented as a list of frames (alist stack).
;;;; Each frame is an alist of (name-string . value) pairs.
;;;; Lookup walks from innermost to outermost frame.

(defpackage #:recurya/wardlisp/environment
  (:use #:cl)
  (:export #:make-env
           #:env-lookup
           #:env-extend
           #:env-define!))

(in-package #:recurya/wardlisp/environment)

(defun make-env ()
  "Create an empty environment (no frames)."
  nil)

(defun env-extend (env bindings)
  "Extend ENV with a new frame containing BINDINGS (alist of name.value pairs)."
  (cons (copy-alist bindings) env))

(defun env-lookup (env name)
  "Look up NAME in ENV. Signals error if unbound."
  (dolist (frame env)
    (let ((pair (assoc name frame :test #'string=)))
      (when pair (return-from env-lookup (cdr pair)))))
  (error "Unbound variable: ~A" name))

(defun env-define! (env name value)
  "Define NAME in the innermost frame of ENV."
  (when (null env)
    (error "Cannot define in empty environment"))
  (let* ((frame (car env))
         (pair (assoc name frame :test #'string=)))
    (if pair
        (setf (cdr pair) value)
        (setf (car env) (acons name value frame))))
  value)
