;;;; tests/wardlisp/builtins.lisp --- Tests for WardLisp built-in functions.

(defpackage #:recurya/tests/wardlisp/builtins
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil)
  (:import-from #:recurya/wardlisp/builtins
                #:lookup-builtin
                #:builtin-names))

(in-package #:recurya/tests/wardlisp/builtins)

(deftest builtin-registry
  (testing "known builtins are found"
    (ok (functionp (lookup-builtin "+")))
    (ok (functionp (lookup-builtin "cons")))
    (ok (functionp (lookup-builtin "null?"))))

  (testing "unknown names return nil"
    (ok (null (lookup-builtin "eval")))
    (ok (null (lookup-builtin "system")))))

(deftest arithmetic
  (testing "addition"
    (ok (= 5 (funcall (lookup-builtin "+") '(2 3)))))

  (testing "subtraction"
    (ok (= 3 (funcall (lookup-builtin "-") '(5 2)))))

  (testing "multiplication"
    (ok (= 12 (funcall (lookup-builtin "*") '(3 4)))))

  (testing "division"
    (ok (= 5 (funcall (lookup-builtin "/") '(10 2)))))

  (testing "modulo"
    (ok (= 1 (funcall (lookup-builtin "mod") '(7 3))))))

(deftest comparison
  (testing "equal"
    (ok (eq wardlisp-true (funcall (lookup-builtin "=") '(3 3))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "=") '(3 4)))))

  (testing "less than"
    (ok (eq wardlisp-true (funcall (lookup-builtin "<") '(1 2))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "<") '(2 1))))))

(deftest list-ops
  (testing "cons"
    (let ((result (funcall (lookup-builtin "cons") (list 1 wardlisp-nil))))
      (ok (= 1 (car result)))
      (ok (eq wardlisp-nil (cdr result)))))

  (testing "car and cdr"
    (let ((pair (cons 1 (cons 2 wardlisp-nil))))
      (ok (= 1 (funcall (lookup-builtin "car") (list pair))))
      (ok (= 2 (car (funcall (lookup-builtin "cdr") (list pair)))))))

  (testing "null?"
    (ok (eq wardlisp-true (funcall (lookup-builtin "null?") (list wardlisp-nil))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "null?") (list 42)))))

  (testing "list"
    (let ((result (funcall (lookup-builtin "list") '(1 2 3))))
      (ok (= 1 (car result)))
      (ok (= 3 (car (cdr (cdr result)))))))

  (testing "length"
    (let ((lst (cons 1 (cons 2 (cons 3 wardlisp-nil)))))
      (ok (= 3 (funcall (lookup-builtin "length") (list lst))))))

  (testing "pair?"
    (ok (eq wardlisp-true (funcall (lookup-builtin "pair?") (list (cons 1 2)))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "pair?") (list 42))))))

(deftest type-predicates
  (testing "number?"
    (ok (eq wardlisp-true (funcall (lookup-builtin "number?") '(42))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "number?") (list :up)))))

  (testing "boolean?"
    (ok (eq wardlisp-true (funcall (lookup-builtin "boolean?") (list wardlisp-true))))
    (ok (eq wardlisp-false (funcall (lookup-builtin "boolean?") '(1))))))

(deftest utility
  (testing "alist-ref"
    (let ((alist (cons (cons :x 10) (cons (cons :y 20) wardlisp-nil))))
      (ok (= 10 (funcall (lookup-builtin "alist-ref") (list :x alist)))))))
