;;;; game/puzzles/contains.lisp --- Puzzle: list membership check.

(defpackage #:recurya/game/puzzles/contains
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types #:wardlisp-true #:wardlisp-false)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-contains-puzzle))

(in-package #:recurya/game/puzzles/contains)

(defun make-contains-puzzle ()
  "Puzzle: Write (contains? lst item) that checks list membership."
  (make-puzzle
   :id :contains
   :title "contains?"
   :description "Write (contains? lst item) that returns #t if item is in the list, #f otherwise.
Use recursion with car/cdr."
   :signature "(contains? lst item)"
   :hint "Base case: empty list returns #f. Recursive: check car, else search cdr."
   :difficulty 1
   :test-cases
   (list
    (make-test-case :input "(contains? '(1 2 3) 2)" :expected wardlisp-true
                    :description "element present")
    (make-test-case :input "(contains? '(1 2 3) 5)" :expected wardlisp-false
                    :description "element absent")
    (make-test-case :input "(contains? '() 1)" :expected wardlisp-false
                    :description "empty list")
    (make-test-case :input "(contains? '(1) 1)" :expected wardlisp-true
                    :description "single element match")
    (make-test-case :input "(contains? '(:up :down :left) :down)" :expected wardlisp-true
                    :description "keyword search"))))
