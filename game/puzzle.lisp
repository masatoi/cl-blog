;;;; game/puzzle.lisp --- Puzzle definition and grading system.
;;;;
;;;; Puzzles are defined as structs with test cases. The grading flow:
;;;; 1. Eval user code to register function definitions
;;;; 2. Run each test case in the same environment
;;;; 3. Compare results with expected values
;;;; 4. Collect metrics and return structured results

(defpackage #:recurya/game/puzzle
  (:use #:cl)
  (:import-from #:recurya/wardlisp/evaluator
                #:eval-program
                #:make-execution-limits
                #:execution-result-value
                #:execution-result-fuel-used
                #:execution-result-cons-used
                #:execution-result-depth-reached
                #:execution-result-output
                #:execution-result-error)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-equal
                #:wardlisp->string)
  (:export #:puzzle
           #:make-puzzle
           #:puzzle-id
           #:puzzle-title
           #:puzzle-description
           #:puzzle-signature
           #:puzzle-hint
           #:puzzle-test-cases
           #:puzzle-difficulty
           #:make-test-case
           #:test-case-input
           #:test-case-expected
           #:test-case-description
           #:run-puzzle
           #:puzzle-result
           #:puzzle-result-passed
           #:puzzle-result-failed
           #:puzzle-result-total
           #:puzzle-result-test-results
           #:puzzle-result-fuel-used
           #:puzzle-result-cons-used
           #:puzzle-result-depth-reached
           #:puzzle-result-error
           #:test-result
           #:test-result-passed-p
           #:test-result-expected
           #:test-result-actual
           #:test-result-description
           #:test-result-error))

(in-package #:recurya/game/puzzle)

;;; --- Data Structures ---

(defstruct puzzle
  "A WardLisp puzzle definition."
  (id nil :type keyword)
  (title "" :type string)
  (description "" :type string)
  (signature "" :type string)
  (hint nil)
  (test-cases nil :type list)
  (difficulty 1 :type fixnum))

(defstruct test-case
  "A single test case for a puzzle."
  (input "" :type string)
  (expected nil)
  (description "" :type string))

;;; --- Results ---

(defstruct test-result
  "Result of running one test case."
  (passed-p nil :type boolean)
  (expected nil)
  (actual nil)
  (description "" :type string)
  (error nil))

(defstruct puzzle-result
  "Aggregate result of grading a puzzle."
  (passed 0 :type fixnum)
  (failed 0 :type fixnum)
  (total 0 :type fixnum)
  (test-results nil :type list)
  (fuel-used 0 :type fixnum)
  (cons-used 0 :type fixnum)
  (depth-reached 0 :type fixnum)
  (error nil))

;;; --- Grading ---

(defparameter *puzzle-limits*
  (make-execution-limits :fuel 10000 :max-cons 5000 :max-depth 100 :max-output 4096)
  "Default resource limits for puzzle execution.")

(defun run-puzzle (puzzle user-code)
  "Grade user code against puzzle test cases. Returns a puzzle-result."
  (let ((test-results nil)
        (total-fuel 0)
        (total-cons 0)
        (max-depth 0))
    ;; Run each test case with user definitions prepended
    (dolist (tc (puzzle-test-cases puzzle))
      (let* ((full-code (format nil "~A~%~A" user-code (test-case-input tc)))
             (result (eval-program full-code :limits *puzzle-limits*)))
        (incf total-fuel (execution-result-fuel-used result))
        (incf total-cons (execution-result-cons-used result))
        (setf max-depth (max max-depth (execution-result-depth-reached result)))
        (if (execution-result-error result)
            (push (make-test-result
                   :passed-p nil
                   :expected (test-case-expected tc)
                   :actual nil
                   :description (test-case-description tc)
                   :error (execution-result-error result))
                  test-results)
            (let ((passed (wardlisp-equal
                           (execution-result-value result)
                           (test-case-expected tc))))
              (push (make-test-result
                     :passed-p passed
                     :expected (test-case-expected tc)
                     :actual (execution-result-value result)
                     :description (test-case-description tc))
                    test-results)))))
    (let ((results (nreverse test-results)))
      (make-puzzle-result
       :passed (count-if #'test-result-passed-p results)
       :failed (count-if-not #'test-result-passed-p results)
       :total (length results)
       :test-results results
       :fuel-used total-fuel
       :cons-used total-cons
       :depth-reached max-depth))))
