;;;; tests/wardlisp/environment.lisp --- Tests for WardLisp lexical environment.

(defpackage #:recurya/tests/wardlisp/environment
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/environment
                #:make-env
                #:env-lookup
                #:env-extend
                #:env-define!))

(in-package #:recurya/tests/wardlisp/environment)

(deftest lookup
  (testing "lookup finds variable in current frame"
    (let ((env (env-extend (make-env) '(("x" . 42)))))
      (ok (= 42 (env-lookup env "x")))))

  (testing "lookup finds variable in outer frame"
    (let* ((outer (env-extend (make-env) '(("x" . 10))))
           (inner (env-extend outer '(("y" . 20)))))
      (ok (= 10 (env-lookup inner "x")))))

  (testing "inner shadows outer"
    (let* ((outer (env-extend (make-env) '(("x" . 10))))
           (inner (env-extend outer '(("x" . 99)))))
      (ok (= 99 (env-lookup inner "x")))))

  (testing "unbound variable signals error"
    (let ((env (make-env)))
      (ok (signals error (env-lookup env "z"))))))

(deftest define
  (testing "define adds to current frame"
    (let ((env (env-extend (make-env) nil)))
      (env-define! env "x" 42)
      (ok (= 42 (env-lookup env "x")))))

  (testing "define overwrites in current frame"
    (let ((env (env-extend (make-env) '(("x" . 1)))))
      (env-define! env "x" 2)
      (ok (= 2 (env-lookup env "x"))))))
