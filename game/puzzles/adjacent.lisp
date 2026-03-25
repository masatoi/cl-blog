;;;; game/puzzles/adjacent.lisp --- Puzzle: adjacent point detection.

(defpackage #:recurya/game/puzzles/adjacent
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types #:wardlisp-true #:wardlisp-false)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-adjacent-puzzle))

(in-package #:recurya/game/puzzles/adjacent)

(defun make-adjacent-puzzle ()
  "Puzzle: Write (adjacent? p1 p2) for Manhattan distance = 1."
  (make-puzzle
   :id :adjacent
   :title "adjacent?"
   :description "Write (adjacent? p1 p2) that returns #t if two (row col) points
are horizontally or vertically adjacent (Manhattan distance = 1)."
   :signature "(adjacent? p1 p2)"
   :hint "Use abs and arithmetic on car/cdr of each point."
   :difficulty 1
   :test-cases
   (list
    (make-test-case :input "(adjacent? '(0 0) '(0 1))" :expected wardlisp-true
                    :description "horizontal neighbor")
    (make-test-case :input "(adjacent? '(0 0) '(1 0))" :expected wardlisp-true
                    :description "vertical neighbor")
    (make-test-case :input "(adjacent? '(0 0) '(1 1))" :expected wardlisp-false
                    :description "diagonal is not adjacent")
    (make-test-case :input "(adjacent? '(0 0) '(0 0))" :expected wardlisp-false
                    :description "same point is not adjacent")
    (make-test-case :input "(adjacent? '(3 4) '(3 5))" :expected wardlisp-true
                    :description "non-origin adjacent"))))
