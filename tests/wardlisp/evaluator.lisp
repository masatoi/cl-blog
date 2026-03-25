;;;; tests/wardlisp/evaluator.lisp --- Tests for WardLisp evaluator.

(defpackage #:recurya/tests/wardlisp/evaluator
  (:use #:cl #:rove)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false
                #:wardlisp-nil
                #:wardlisp-nil-p
                #:wardlisp-equal
                #:wardlisp->string)
  (:import-from #:recurya/wardlisp/evaluator
                #:eval-program
                #:make-execution-limits
                #:execution-result-value
                #:execution-result-fuel-used
                #:execution-result-cons-used
                #:execution-result-output
                #:execution-result-error))

(in-package #:recurya/tests/wardlisp/evaluator)

;;; Helper
(defun run (code &key (fuel 10000) (max-cons 5000) (max-depth 100))
  "Run WardLisp code and return the result value."
  (let ((result (eval-program code
                  :limits (make-execution-limits
                            :fuel fuel :max-cons max-cons
                            :max-depth max-depth))))
    (execution-result-value result)))

(defun run-result (code &key (fuel 10000) (max-cons 5000) (max-depth 100))
  "Run WardLisp code and return the full result struct."
  (eval-program code
    :limits (make-execution-limits
              :fuel fuel :max-cons max-cons :max-depth max-depth)))

(deftest self-evaluating
  (testing "numbers"
    (ok (= 42 (run "42"))))

  (testing "booleans"
    (ok (eq wardlisp-true (run "#t")))
    (ok (eq wardlisp-false (run "#f"))))

  (testing "keywords"
    (ok (eq :up (run ":up")))))

(deftest arithmetic
  (testing "basic ops"
    (ok (= 5 (run "(+ 2 3)")))
    (ok (= 6 (run "(* 2 3)")))
    (ok (= 10 (run "(+ 1 2 3 4)")))))

(deftest special-forms
  (testing "if true branch"
    (ok (= 1 (run "(if #t 1 2)"))))

  (testing "if false branch"
    (ok (= 2 (run "(if #f 1 2)"))))

  (testing "let binding"
    (ok (= 3 (run "(let ((x 1) (y 2)) (+ x y))"))))

  (testing "define and use"
    (ok (= 42 (run "(define x 42) x"))))

  (testing "begin returns last"
    (ok (= 3 (run "(begin 1 2 3)"))))

  (testing "quote"
    (ok (wardlisp-equal (run "'(1 2 3)")
                        (run "(list 1 2 3)")))))

(deftest lambda-and-closure
  (testing "lambda application"
    (ok (= 5 (run "((lambda (x) (+ x 2)) 3)"))))

  (testing "closure captures environment"
    (ok (= 10 (run "(define add5 (lambda (x) (+ x 5))) (add5 5)"))))

  (testing "higher-order function"
    (ok (= 9 (run "(define apply-twice (lambda (f x) (f (f x))))
                    (define inc (lambda (x) (+ x 1)))
                    (apply-twice inc 7)")))))

(deftest recursion
  (testing "factorial"
    (ok (= 120 (run "(define fact (lambda (n)
                        (if (= n 0) 1 (* n (fact (- n 1))))))
                      (fact 5)"))))

  (testing "list operations"
    (ok (= 6 (run "(define sum (lambda (lst)
                      (if (null? lst) 0
                          (+ (car lst) (sum (cdr lst))))))
                    (sum '(1 2 3))")))))

(deftest and-or
  (testing "and short-circuits"
    (ok (eq wardlisp-false (run "(and #f (/ 1 0))"))))

  (testing "or short-circuits"
    (ok (eq wardlisp-true (run "(or #t (/ 1 0))")))))

(deftest fuel-limit
  (testing "fuel exhaustion"
    (let ((result (run-result "(define loop (lambda () (loop))) (loop)" :fuel 50)))
      (ok (execution-result-error result))
      (ok (search "uel" (string-downcase (execution-result-error result)))))))

(deftest depth-limit
  (testing "depth exhaustion"
    (let ((result (run-result "(define deep (lambda (n) (deep (+ n 1)))) (deep 0)"
                              :max-depth 10)))
      (ok (execution-result-error result))
      (ok (search "epth" (string-downcase (execution-result-error result)))))))

(deftest cons-limit
  (testing "cons exhaustion"
    (let ((result (run-result
                    "(define make-list (lambda (n)
                       (if (= n 0) '() (cons n (make-list (- n 1))))))
                     (make-list 10000)"
                    :max-cons 50)))
      (ok (execution-result-error result))
      (ok (search "ons" (string-downcase (execution-result-error result)))))))

(deftest metrics-tracking
  (testing "fuel usage is tracked"
    (let ((result (run-result "(+ 1 2)")))
      (ok (> (execution-result-fuel-used result) 0)))))

(deftest error-handling
  (testing "unbound variable"
    (let ((result (run-result "undefined-var")))
      (ok (execution-result-error result))))

  (testing "type error in arithmetic"
    (let ((result (run-result "(+ 1 #t)")))
      (ok (execution-result-error result)))))

(deftest deterministic
  (testing "same input produces same result"
    (let ((code "(define fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10)"))
      (ok (= (run code) (run code) (run code))))))
