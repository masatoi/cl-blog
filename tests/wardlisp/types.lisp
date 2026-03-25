;;;; tests/wardlisp/types.lisp --- Tests for WardLisp value types.

(defpackage #:recurya/tests/wardlisp/types
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-number-p
                #:wardlisp-boolean-p
                #:wardlisp-symbol-p
                #:wardlisp-list-p
                #:wardlisp-nil-p
                #:wardlisp-closure-p
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:make-closure
                #:closure-params
                #:closure-body
                #:closure-env
                #:wardlisp-equal
                #:wardlisp->string))

(in-package #:recurya/tests/wardlisp/types)

(deftest type-predicates
  (testing "numbers are recognized"
    (ok (wardlisp-number-p 42))
    (ok (wardlisp-number-p 3/4))
    (ok (not (wardlisp-number-p "hello"))))

  (testing "booleans are recognized"
    (ok (wardlisp-boolean-p wardlisp-true))
    (ok (wardlisp-boolean-p wardlisp-false))
    (ok (not (wardlisp-boolean-p 1))))

  (testing "symbols are keywords"
    (ok (wardlisp-symbol-p :up))
    (ok (wardlisp-symbol-p :foo))
    (ok (not (wardlisp-symbol-p 42))))

  (testing "nil value"
    (ok (wardlisp-nil-p wardlisp-nil))
    (ok (not (wardlisp-nil-p nil))))

  (testing "lists"
    (ok (wardlisp-list-p (cons 1 (cons 2 wardlisp-nil))))
    (ok (not (wardlisp-list-p 42)))))

(deftest closures
  (testing "closure creation and access"
    (let ((c (make-closure '("x") '((+ x 1)) nil)))
      (ok (wardlisp-closure-p c))
      (ok (equal (closure-params c) '("x")))
      (ok (equal (closure-body c) '((+ x 1)))))))

(deftest equality
  (testing "number equality"
    (ok (wardlisp-equal 42 42))
    (ok (not (wardlisp-equal 42 43))))

  (testing "boolean equality"
    (ok (wardlisp-equal wardlisp-true wardlisp-true))
    (ok (not (wardlisp-equal wardlisp-true wardlisp-false))))

  (testing "symbol equality"
    (ok (wardlisp-equal :up :up))
    (ok (not (wardlisp-equal :up :down))))

  (testing "list equality"
    (ok (wardlisp-equal (cons 1 (cons 2 wardlisp-nil))
                        (cons 1 (cons 2 wardlisp-nil))))))

(deftest display
  (testing "value display"
    (ok (string= (wardlisp->string 42) "42"))
    (ok (string= (wardlisp->string wardlisp-true) "#t"))
    (ok (string= (wardlisp->string wardlisp-false) "#f"))
    (ok (string= (wardlisp->string wardlisp-nil) "()"))
    (ok (string= (wardlisp->string :up) ":up"))))
