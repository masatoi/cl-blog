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
(defun eval-code (code &key (fuel 10000) (max-cons 5000) (max-depth 100))
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
    (ok (= 42 (eval-code "42"))))

  (testing "booleans"
    (ok (eq wardlisp-true (eval-code "#t")))
    (ok (eq wardlisp-false (eval-code "#f"))))

  (testing "keywords"
    (ok (eq :up (eval-code ":up")))))

(deftest arithmetic
  (testing "basic ops"
    (ok (= 5 (eval-code "(+ 2 3)")))
    (ok (= 6 (eval-code "(* 2 3)")))
    (ok (= 10 (eval-code "(+ 1 2 3 4)")))))

(deftest special-forms
  (testing "if true branch"
    (ok (= 1 (eval-code "(if #t 1 2)"))))

  (testing "if false branch"
    (ok (= 2 (eval-code "(if #f 1 2)"))))

  (testing "let binding"
    (ok (= 3 (eval-code "(let ((x 1) (y 2)) (+ x y))"))))

  (testing "define and use"
    (ok (= 42 (eval-code "(define x 42) x"))))

  (testing "begin returns last"
    (ok (= 3 (eval-code "(begin 1 2 3)"))))

  (testing "quote"
    (ok (wardlisp-equal (eval-code "'(1 2 3)")
                        (eval-code "(list 1 2 3)")))))

(deftest lambda-and-closure
  (testing "lambda application"
    (ok (= 5 (eval-code "((lambda (x) (+ x 2)) 3)"))))

  (testing "closure captures environment"
    (ok (= 10 (eval-code "(define add5 (lambda (x) (+ x 5))) (add5 5)"))))

  (testing "higher-order function"
    (ok (= 9 (eval-code "(define apply-twice (lambda (f x) (f (f x))))
                    (define inc (lambda (x) (+ x 1)))
                    (apply-twice inc 7)")))))

(deftest recursion
  (testing "factorial"
    (ok (= 120 (eval-code "(define fact (lambda (n)
                        (if (= n 0) 1 (* n (fact (- n 1))))))
                      (fact 5)"))))

  (testing "list operations"
    (ok (= 6 (eval-code "(define sum (lambda (lst)
                      (if (null? lst) 0
                          (+ (car lst) (sum (cdr lst))))))
                    (sum '(1 2 3))")))))

(deftest and-or
  (testing "and short-circuits"
    (ok (eq wardlisp-false (eval-code "(and #f (/ 1 0))"))))

  (testing "or short-circuits"
    (ok (eq wardlisp-true (eval-code "(or #t (/ 1 0))")))))

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
                     (make-list 200)"
                    :max-cons 50 :max-depth 500 :fuel 50000)))
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
      (ok (= (eval-code code) (eval-code code) (eval-code code))))))

(deftest print-output
  (testing "print captures output"
    (let ((result (run-result "(print 42) (print (+ 1 2))")))
      (ok (null (execution-result-error result)))
      (ok (search "42" (execution-result-output result)))
      (ok (search "3" (execution-result-output result)))))

  (testing "print output limit"
    (let ((result (run-result
                    "(define (spam n) (if (= n 0) 0 (begin (print n) (spam (- n 1))))) (spam 10000)"
                    :fuel 50000)))
      (ok (execution-result-error result))
      (ok (search "utput" (string-downcase (execution-result-error result)))))))
