;;;; game/puzzle.lisp --- Puzzle definition and grading system.
;;;;
;;;; Puzzles are defined as structs with test cases. The grading flow:
;;;; 1. Eval user code to register function definitions
;;;; 2. Run each test case in the same environment
;;;; 3. Compare results with expected values
;;;; 4. Collect metrics and return structured results

(defpackage #:recurya/game/puzzle
  (:use #:cl)
  (:import-from #:wardlisp
                #:evaluate
                #:print-value)
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

(defparameter *puzzle-fuel* 10000
  "Default fuel limit for puzzle execution.")

(defparameter *puzzle-max-cons* 5000
  "Default cons limit for puzzle execution.")

(defparameter *puzzle-max-depth* 100
  "Default depth limit for puzzle execution.")

(defparameter *puzzle-max-output* 4096
  "Default output limit for puzzle execution.")

(defparameter *puzzle-timeout* 5
  "Default timeout in seconds for puzzle execution.")

(defun run-puzzle (puzzle user-code)
  "Grade user code against puzzle test cases. Returns a puzzle-result."
  (let ((test-results nil)
        (total-fuel 0)
        (total-cons 0)
        (max-depth 0))
    (dolist (tc (puzzle-test-cases puzzle))
      (let ((full-code (format nil "~A~%~A" user-code (test-case-input tc))))
        (multiple-value-bind (result metrics)
            (evaluate full-code
                      :fuel *puzzle-fuel*
                      :max-cons *puzzle-max-cons*
                      :max-depth *puzzle-max-depth*
                      :max-output *puzzle-max-output*
                      :timeout *puzzle-timeout*)
          (incf total-fuel (getf metrics :steps-used))
          (incf total-cons (getf metrics :cons-allocated))
          (setf max-depth (max max-depth (getf metrics :max-depth-reached)))
          (if (getf metrics :error-message)
              (push (make-test-result
                     :passed-p nil
                     :expected (test-case-expected tc)
                     :actual nil
                     :description (test-case-description tc)
                     :error (getf metrics :error-message))
                    test-results)
              (let* ((expected-str (if (stringp (test-case-expected tc))
                                       (test-case-expected tc)
                                       (print-value (test-case-expected tc))))
                     (passed (string= (print-value result) expected-str)))
                (push (make-test-result
                       :passed-p passed
                       :expected (test-case-expected tc)
                       :actual result
                       :description (test-case-description tc))
                      test-results))))))
    (let ((results (nreverse test-results)))
      (make-puzzle-result
       :passed (count-if #'test-result-passed-p results)
       :failed (count-if-not #'test-result-passed-p results)
       :total (length results)
       :test-results results
       :fuel-used total-fuel
       :cons-used total-cons
       :depth-reached max-depth))))
