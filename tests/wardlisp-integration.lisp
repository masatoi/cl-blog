;;;; tests/wardlisp-integration.lisp --- Integration tests for external wardlisp.

(defpackage #:recurya/tests/wardlisp-integration
  (:use #:cl #:rove)
  (:import-from #:wardlisp #:evaluate #:print-value))

(in-package #:recurya/tests/wardlisp-integration)

(deftest basic-evaluation
  (testing "arithmetic"
    (multiple-value-bind (result metrics) (evaluate "(+ 1 2)")
      (ok (= 3 result))
      (ok (null (getf metrics :error-message)))))

  (testing "booleans are t/nil"
    (ok (eq t (evaluate "(= 1 1)")))
    (ok (eq nil (evaluate "(= 1 2)")))))

(deftest resource-limits
  (testing "fuel exhaustion"
    (multiple-value-bind (result metrics)
        (evaluate "(define (loop) (loop)) (loop)" :fuel 50)
      (declare (ignore result))
      (ok (getf metrics :error-message))))

  (testing "depth limit"
    (multiple-value-bind (result metrics)
        (evaluate "(define (deep n) (deep (+ n 1))) (deep 0)" :max-depth 10)
      (declare (ignore result))
      (ok (getf metrics :error-message))))

  (testing "timeout"
    (multiple-value-bind (result metrics)
        (evaluate "(define (spin) (spin)) (spin)" :timeout 1)
      (declare (ignore result))
      (ok (getf metrics :error-message)))))

(deftest print-value-display
  (testing "integers"
    (ok (string= "42" (print-value 42))))
  (testing "booleans"
    (ok (string= "t" (print-value t)))
    (ok (string= "nil" (print-value nil))))
  (testing "keywords"
    (multiple-value-bind (result metrics) (evaluate ":up")
      (declare (ignore metrics))
      (ok (string= ":up" (print-value result))))))

(deftest puzzle-grading-integration
  (testing "correct puzzle solution grades properly"
    (let* ((puzzle (recurya/game/puzzle:make-puzzle
                    :id :test-double
                    :title "double"
                    :description "test"
                    :signature "(double x)"
                    :test-cases (list
                                 (recurya/game/puzzle:make-test-case
                                  :input "(double 3)" :expected 6
                                  :description "double 3"))))
           (result (recurya/game/puzzle:run-puzzle puzzle
                     "(define (double x) (* x 2))")))
      (ok (= 1 (recurya/game/puzzle:puzzle-result-passed result)))
      (ok (= 0 (recurya/game/puzzle:puzzle-result-failed result))))))

(deftest arena-integration
  (testing "arena simulation completes"
    (let ((result (recurya/game/arena:simulate-arena
                   "(define (decide-action state) :wait)"
                   (recurya/game/scenario:default-scenario))))
      (ok (null (recurya/game/arena:arena-result-error result))))))
