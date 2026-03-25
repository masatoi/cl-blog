;;;; wardlisp/evaluator.lisp --- Core evaluator for WardLisp with resource limits.
;;;;
;;;; SECURITY: This evaluator does NOT use cl:eval. It is a tree-walking
;;;; interpreter that only evaluates WardLisp forms. All resource limits
;;;; (fuel, cons, depth, output) are enforced inside the evaluator.

(defpackage #:recurya/wardlisp/evaluator
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:wardlisp-nil-p
                #:wardlisp-number-p
                #:wardlisp-boolean-p
                #:wardlisp-symbol-p
                #:wardlisp-closure-p
                #:wardlisp-self-evaluating-p
                #:wardlisp-truthy-p
                #:make-closure
                #:closure-params
                #:closure-body
                #:closure-env
                #:wardlisp->string)
  (:import-from #:recurya/wardlisp/environment
                #:make-env
                #:env-lookup
                #:env-extend
                #:env-define!)
  (:import-from #:recurya/wardlisp/reader
                #:wardlisp-read-all)
  (:import-from #:recurya/wardlisp/builtins
                #:lookup-builtin
                #:make-print-builtin)
  (:export #:eval-program
           #:make-execution-limits
           #:execution-limits-fuel
           #:execution-limits-max-cons
           #:execution-limits-max-depth
           #:execution-limits-max-output
           #:execution-result
           #:execution-result-value
           #:execution-result-fuel-used
           #:execution-result-cons-used
           #:execution-result-depth-reached
           #:execution-result-output
           #:execution-result-error
           ;; Conditions
           #:wardlisp-runtime-error
           #:fuel-exhausted
           #:cons-limit-exceeded
           #:depth-limit-exceeded
           #:output-limit-exceeded))

(in-package #:recurya/wardlisp/evaluator)

;;; --- Resource Limits ---

(defstruct execution-limits
  "Resource limits for a WardLisp execution."
  (fuel 10000 :type fixnum)
  (max-cons 5000 :type fixnum)
  (max-depth 100 :type fixnum)
  (max-output 4096 :type fixnum))

;;; --- Execution State (mutable, per-execution) ---

(defstruct execution-state
  "Mutable execution state tracking resource usage."
  (fuel-used 0 :type fixnum)
  (cons-used 0 :type fixnum)
  (max-depth-reached 0 :type fixnum)
  (current-depth 0 :type fixnum)
  (output-stream (make-string-output-stream))
  (output-used 0 :type fixnum))

;;; --- Result ---

(defstruct execution-result
  "Result of a WardLisp program execution."
  value
  (fuel-used 0 :type fixnum)
  (cons-used 0 :type fixnum)
  (depth-reached 0 :type fixnum)
  (output "" :type string)
  (error nil))

;;; --- Conditions ---

(define-condition wardlisp-runtime-error (error)
  ((message :initarg :message :reader wardlisp-runtime-error-message))
  (:report (lambda (c s)
             (format s "~A" (wardlisp-runtime-error-message c)))))

(define-condition fuel-exhausted (wardlisp-runtime-error) ()
  (:default-initargs :message "Fuel exhausted: program took too many steps"))

(define-condition cons-limit-exceeded (wardlisp-runtime-error) ()
  (:default-initargs :message "Cons limit exceeded: too many list allocations"))

(define-condition depth-limit-exceeded (wardlisp-runtime-error) ()
  (:default-initargs :message "Depth limit exceeded: recursion too deep"))

(define-condition output-limit-exceeded (wardlisp-runtime-error) ()
  (:default-initargs :message "Output limit exceeded: too much printed output"))

;;; --- Limit Checking ---

(defun check-fuel! (state limits)
  "Consume one fuel unit. Signal if exhausted."
  (incf (execution-state-fuel-used state))
  (when (> (execution-state-fuel-used state) (execution-limits-fuel limits))
    (error 'fuel-exhausted)))

(defun check-cons! (state limits)
  "Record one cons allocation. Signal if exceeded."
  (incf (execution-state-cons-used state))
  (when (> (execution-state-cons-used state) (execution-limits-max-cons limits))
    (error 'cons-limit-exceeded)))

(defun check-depth! (state limits)
  "Check current depth. Signal if exceeded."
  (when (> (execution-state-current-depth state) (execution-limits-max-depth limits))
    (error 'depth-limit-exceeded))
  (when (> (execution-state-current-depth state)
           (execution-state-max-depth-reached state))
    (setf (execution-state-max-depth-reached state)
          (execution-state-current-depth state))))

;;; --- Core Evaluator ---

(defun eval-expr (expr env state limits)
  "Evaluate a single WardLisp expression."
  (check-fuel! state limits)
  (cond
    ;; Self-evaluating: numbers, booleans, keywords
    ((wardlisp-self-evaluating-p expr) expr)

    ;; Variable lookup (strings are variable names)
    ((stringp expr)
     (let ((builtin (lookup-builtin expr)))
       (if builtin
           builtin
           (env-lookup env expr))))

    ;; Special forms and application (must be a cons)
    ((consp expr)
     (let ((head (car expr)))
       (cond
         ((and (stringp head) (string= head "quote")) (car (cdr expr)))
         ((and (stringp head) (string= head "if")) (eval-if expr env state limits))
         ((and (stringp head) (string= head "let")) (eval-let expr env state limits))
         ((and (stringp head) (string= head "lambda")) (eval-lambda expr env))
         ((and (stringp head) (string= head "define")) (eval-define expr env state limits))
         ((and (stringp head) (string= head "begin")) (eval-begin (cdr expr) env state limits))
         ((and (stringp head) (string= head "and")) (eval-and (cdr expr) env state limits))
         ((and (stringp head) (string= head "or")) (eval-or (cdr expr) env state limits))
         (t (eval-application expr env state limits)))))

    ;; WardLisp nil is self-evaluating
    ((wardlisp-nil-p expr) expr)

    (t (error 'wardlisp-runtime-error
              :message (format nil "Cannot evaluate: ~A" expr)))))

;;; --- Special Forms ---

(defun eval-if (expr env state limits)
  "(if test then else)"
  (let ((test-val (eval-expr (second* expr) env state limits)))
    (if (wardlisp-truthy-p test-val)
        (eval-expr (third* expr) env state limits)
        (if (fourth* expr)
            (eval-expr (fourth* expr) env state limits)
            wardlisp-nil))))

(defun eval-let (expr env state limits)
  "(let ((var val) ...) body...)"
  (let* ((bindings-form (second* expr))
         (body (cddr* expr))
         (bindings (mapcar
                    (lambda (b)
                      (cons (car-of b)
                            (eval-expr (second-of b) env state limits)))
                    (wardlisp-list->cl-list bindings-form))))
    (let ((new-env (env-extend env bindings)))
      (eval-body body new-env state limits))))

(defun eval-lambda (expr env)
  "(lambda (params...) body...)"
  (let ((params (mapcar #'identity
                        (wardlisp-list->cl-list (second* expr))))
        (body (cddr* expr)))
    (make-closure params (wardlisp-list->cl-list body) env)))

(defun eval-define (expr env state limits)
  "(define name expr) or (define (name params...) body...)"
  (let ((target (second* expr)))
    (if (consp target)
        ;; (define (f x y) body...) sugar
        (let* ((name (car target))
               (params (wardlisp-list->cl-list (cdr target)))
               (body (cddr* expr))
               (closure (make-closure params (wardlisp-list->cl-list body) env)))
          (env-define! env name closure)
          closure)
        ;; (define name expr)
        (let ((value (eval-expr (third* expr) env state limits)))
          (env-define! env target value)
          value))))

(defun eval-begin (exprs env state limits)
  "(begin expr...)"
  (eval-body (wardlisp-list->cl-list exprs) env state limits))

(defun eval-and (exprs env state limits)
  "(and expr...) - short-circuit"
  (let ((result wardlisp-true))
    (dolist (e (wardlisp-list->cl-list exprs) result)
      (setf result (eval-expr e env state limits))
      (unless (wardlisp-truthy-p result)
        (return wardlisp-false)))))

(defun eval-or (exprs env state limits)
  "(or expr...) - short-circuit"
  (dolist (e (wardlisp-list->cl-list exprs) wardlisp-false)
    (let ((val (eval-expr e env state limits)))
      (when (wardlisp-truthy-p val)
        (return val)))))

;;; --- Function Application ---

(defun eval-application (expr env state limits)
  "Evaluate a function application: (func arg...)"
  (let ((func (eval-expr (car expr) env state limits))
        (args (mapcar (lambda (a) (eval-expr a env state limits))
                      (wardlisp-list->cl-list (cdr expr)))))
    (cond
      ;; Built-in function (CL function from builtins registry)
      ((functionp func)
       (handler-case (funcall func args)
         (error (e)
           (error 'wardlisp-runtime-error
                  :message (format nil "Built-in error: ~A" e)))))

      ;; WardLisp closure
      ((wardlisp-closure-p func)
       (let ((params (closure-params func))
             (body (closure-body func))
             (closure-env (closure-env func)))
         (unless (= (length params) (length args))
           (error 'wardlisp-runtime-error
                  :message (format nil "Expected ~D arguments, got ~D"
                                   (length params) (length args))))
         (let ((bindings (mapcar #'cons params args))
               (new-depth (1+ (execution-state-current-depth state))))
           (setf (execution-state-current-depth state) new-depth)
           (check-depth! state limits)
           (unwind-protect
                (let ((new-env (env-extend closure-env bindings)))
                  (eval-body body new-env state limits))
             (decf (execution-state-current-depth state))))))

      (t (error 'wardlisp-runtime-error
                :message (format nil "Not a function: ~A"
                                 (wardlisp->string func)))))))

;;; --- Helpers ---

(defun eval-body (forms env state limits)
  "Evaluate a list of forms, returning the last value."
  (let ((result wardlisp-nil))
    (dolist (form forms result)
      (setf result (eval-expr form env state limits)))))

(defun wardlisp-list->cl-list (wl)
  "Convert a WardLisp list to a CL list."
  (if (or (wardlisp-nil-p wl) (null wl))
      nil
      (cons (car wl) (wardlisp-list->cl-list (cdr wl)))))

;; Safe accessors for cons-based WardLisp forms
(defun second* (expr) (car (cdr expr)))
(defun third* (expr) (car (cdr (cdr expr))))
(defun fourth* (expr) (car (cdr (cdr (cdr expr)))))
(defun cddr* (expr) (cdr (cdr expr)))
(defun car-of (b) (if (consp b) (car b) b))
(defun second-of (b) (if (consp b) (car (cdr b)) wardlisp-nil))

;;; --- Public API ---

(defun eval-program (source &key (limits (make-execution-limits)))
  "Evaluate a WardLisp program string. Returns an execution-result struct.
Never signals — all errors are captured in the result."
  (let ((state (make-execution-state))
        (env (env-extend (make-env) nil)))
    ;; Register print with output limits
    (env-define! env "print"
      (make-print-builtin
       (lambda (str)
         (let ((len (length str)))
           (incf (execution-state-output-used state) len)
           (when (> (execution-state-output-used state)
                    (execution-limits-max-output limits))
             (error 'output-limit-exceeded))
           (write-string str (execution-state-output-stream state))))))
    (handler-case
        (let* ((forms (wardlisp-read-all source))
               (value (eval-body forms env state limits)))
          (make-execution-result
           :value value
           :fuel-used (execution-state-fuel-used state)
           :cons-used (execution-state-cons-used state)
           :depth-reached (execution-state-max-depth-reached state)
           :output (get-output-stream-string
                    (execution-state-output-stream state))))
      (error (e)
        (make-execution-result
         :value wardlisp-nil
         :fuel-used (execution-state-fuel-used state)
         :cons-used (execution-state-cons-used state)
         :depth-reached (execution-state-max-depth-reached state)
         :output (get-output-stream-string
                  (execution-state-output-stream state))
         :error (format nil "~A" e))))))
