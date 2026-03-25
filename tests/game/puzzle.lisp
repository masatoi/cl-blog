;;;; tests/game/puzzle.lisp --- Tests for puzzle grading system.

(defpackage #:recurya/tests/game/puzzle
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false)
  (:import-from #:recurya/game/puzzle
                #:make-puzzle
                #:make-test-case
                #:run-puzzle
                #:puzzle-result-passed
                #:puzzle-result-failed
                #:puzzle-result-total
                #:puzzle-result-test-results
                #:puzzle-result-error
                #:test-result-passed-p
                #:test-result-expected
                #:test-result-actual))

(in-package #:recurya/tests/game/puzzle)

(defun make-simple-puzzle ()
  "A trivial puzzle: define (double x) that returns x*2."
  (make-puzzle
   :id :double
   :title "double"
   :description "Write (double x) that returns x * 2"
   :signature "(double x)"
   :test-cases (list
                (make-test-case :input "(double 3)" :expected 6
                                :description "double 3")
                (make-test-case :input "(double 0)" :expected 0
                                :description "double 0")
                (make-test-case :input "(double -5)" :expected -10
                                :description "double negative"))))

(deftest grading-correct-solution
  (testing "correct solution passes all tests"
    (let ((result (run-puzzle (make-simple-puzzle)
                              "(define (double x) (* x 2))")))
      (ok (= 3 (puzzle-result-passed result)))
      (ok (= 0 (puzzle-result-failed result)))
      (ok (null (puzzle-result-error result))))))

(deftest grading-wrong-solution
  (testing "wrong solution fails some tests"
    (let ((result (run-puzzle (make-simple-puzzle)
                              "(define (double x) (+ x x x))")))
      ;; (+ x x x) = 3x, not 2x
      (ok (> (puzzle-result-failed result) 0)))))

(deftest grading-syntax-error
  (testing "syntax error is captured"
    (let ((result (run-puzzle (make-simple-puzzle) "(define double")))
      (ok (puzzle-result-error result)))))

(deftest grading-fuel-exhaustion
  (testing "infinite loop is caught"
    (let ((result (run-puzzle (make-simple-puzzle)
                              "(define (double x) (double x))")))
      (ok (puzzle-result-error result)))))

(deftest grading-metrics
  (testing "test results include actual values"
    (let* ((result (run-puzzle (make-simple-puzzle)
                               "(define (double x) (* x 2))"))
           (first-test (first (puzzle-result-test-results result))))
      (ok (test-result-passed-p first-test))
      (ok (= 6 (test-result-actual first-test))))))
