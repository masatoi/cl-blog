;;;; tests/wardlisp/reader.lisp --- Tests for WardLisp S-expression reader.

(defpackage #:recurya/tests/wardlisp/reader
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:wardlisp-equal)
  (:import-from #:recurya/wardlisp/reader
                #:wardlisp-read
                #:wardlisp-read-all
                #:wardlisp-read-error))

(in-package #:recurya/tests/wardlisp/reader)

(deftest read-atoms
  (testing "integers"
    (ok (= 42 (wardlisp-read "42")))
    (ok (= -7 (wardlisp-read "-7")))
    (ok (= 0 (wardlisp-read "0"))))

  (testing "booleans"
    (ok (eq wardlisp-true (wardlisp-read "#t")))
    (ok (eq wardlisp-false (wardlisp-read "#f"))))

  (testing "symbols become variable names (strings)"
    (ok (string= "foo" (wardlisp-read "foo")))
    (ok (string= "+" (wardlisp-read "+")))
    (ok (string= "null?" (wardlisp-read "null?"))))

  (testing "keywords"
    (ok (eq :up (wardlisp-read ":up")))
    (ok (eq :down (wardlisp-read ":down")))))

(deftest read-lists
  (testing "empty list"
    (ok (eq wardlisp-nil (wardlisp-read "()"))))

  (testing "simple list"
    (let ((result (wardlisp-read "(1 2 3)")))
      (ok (= 1 (car result)))
      (ok (= 3 (car (cdr (cdr result)))))))

  (testing "nested list"
    (let ((result (wardlisp-read "(+ (* 2 3) 1)")))
      (ok (string= "+" (car result)))))

  (testing "quote shorthand"
    (let ((result (wardlisp-read "'(1 2)")))
      (ok (string= "quote" (car result))))))

(deftest read-multiple
  (testing "read-all parses multiple forms"
    (let ((forms (wardlisp-read-all "(define x 1) (+ x 2)")))
      (ok (= 2 (length forms))))))

(deftest read-errors
  (testing "unclosed paren"
    (ok (signals wardlisp-read-error (wardlisp-read "(1 2"))))

  (testing "unexpected close paren"
    (ok (signals wardlisp-read-error (wardlisp-read ")"))))

  (testing "empty input"
    (ok (signals wardlisp-read-error (wardlisp-read "")))))

(deftest read-whitespace-and-comments
  (testing "skips whitespace"
    (ok (= 42 (wardlisp-read "  42  "))))

  (testing "skips line comments"
    (ok (= 42 (wardlisp-read ";; hello\n42")))))
