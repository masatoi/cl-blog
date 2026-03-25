;;;; wardlisp/builtins.lisp --- Whitelisted built-in functions for WardLisp.
;;;;
;;;; SECURITY: Only these functions are accessible from user code.
;;;; No CL function is callable unless explicitly registered here.

(defpackage #:recurya/wardlisp/builtins
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:wardlisp-nil-p
                #:wardlisp-number-p
                #:wardlisp-boolean-p
                #:wardlisp-symbol-p
                #:wardlisp-list-p
                #:wardlisp-equal
                #:wardlisp->string)
  (:export #:lookup-builtin
           #:builtin-names
           #:make-print-builtin))

(in-package #:recurya/wardlisp/builtins)

(defvar *builtins* (make-hash-table :test 'equal)
  "Registry of built-in functions. Maps name string to function.")

(defmacro defbuiltin (name params &body body)
  "Define a built-in function. PARAMS is the lambda list for the builtin."
  `(setf (gethash ,name *builtins*)
         (lambda ,params ,@body)))

;;; --- Arithmetic ---

(defbuiltin "+" (args) (apply #'+ args))
(defbuiltin "-" (args) (apply #'- args))
(defbuiltin "*" (args) (apply #'* args))
(defbuiltin "/" (args) (apply #'/ args))
(defbuiltin "mod" (args) (mod (first args) (second args)))
(defbuiltin "abs" (args) (abs (first args)))

;;; --- Comparison ---

(defun bool (val) (if val wardlisp-true wardlisp-false))

(defbuiltin "=" (args) (bool (= (first args) (second args))))
(defbuiltin "<" (args) (bool (< (first args) (second args))))
(defbuiltin ">" (args) (bool (> (first args) (second args))))
(defbuiltin "<=" (args) (bool (<= (first args) (second args))))
(defbuiltin ">=" (args) (bool (>= (first args) (second args))))
(defbuiltin "equal?" (args) (bool (wardlisp-equal (first args) (second args))))

;;; --- Logic ---

(defbuiltin "not" (args)
  (if (eq (first args) wardlisp-false) wardlisp-true wardlisp-false))

;;; --- List Operations ---

(defbuiltin "cons" (args) (cons (first args) (second args)))
(defbuiltin "car" (args) (car (first args)))
(defbuiltin "cdr" (args) (cdr (first args)))

(defbuiltin "list" (args)
  (if (null args)
      wardlisp-nil
      (reduce (lambda (a b) (cons a b))
              args :from-end t :initial-value wardlisp-nil)))

(defbuiltin "null?" (args) (bool (wardlisp-nil-p (first args))))
(defbuiltin "pair?" (args) (bool (consp (first args))))

(defbuiltin "length" (args)
  (labels ((len (lst acc)
             (if (wardlisp-nil-p lst) acc
                 (len (cdr lst) (1+ acc)))))
    (len (first args) 0)))

(defbuiltin "append" (args)
  (labels ((app (a b)
             (if (wardlisp-nil-p a) b
                 (cons (car a) (app (cdr a) b)))))
    (app (first args) (second args))))

;;; --- Type Predicates ---

(defbuiltin "number?" (args) (bool (wardlisp-number-p (first args))))
(defbuiltin "boolean?" (args) (bool (wardlisp-boolean-p (first args))))
(defbuiltin "symbol?" (args) (bool (wardlisp-symbol-p (first args))))
(defbuiltin "list?" (args) (bool (wardlisp-list-p (first args))))

;;; --- Utility ---

(defbuiltin "alist-ref" (args)
  (let ((key (first args))
        (alist (second args)))
    (labels ((find-key (lst)
               (cond
                 ((wardlisp-nil-p lst) wardlisp-nil)
                 ((wardlisp-equal key (car (car lst))) (cdr (car lst)))
                 (t (find-key (cdr lst))))))
      (find-key alist))))

;;; --- Print (created per-execution with output limit) ---

(defun make-print-builtin (output-fn)
  "Create a print builtin. OUTPUT-FN is called with the string to output.
It should signal an error if output limit is exceeded."
  (lambda (args)
    (let* ((val (first args))
           (str (format nil "~A~%" (wardlisp->string val))))
      (funcall output-fn str)
      wardlisp-nil)))

;;; --- Public API ---

(defun lookup-builtin (name)
  "Look up a built-in function by name. Returns function or NIL."
  (gethash name *builtins*))

(defun builtin-names ()
  "Return list of all built-in function names."
  (let ((names nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k names)) *builtins*)
    (sort names #'string<)))
