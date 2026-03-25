;;;; game/puzzles/nearest-point.lisp --- Puzzle: find nearest point.

(defpackage #:recurya/game/puzzles/nearest-point
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types #:wardlisp-nil)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-nearest-point-puzzle))

(in-package #:recurya/game/puzzles/nearest-point)

(defun make-nearest-point-puzzle ()
  "Puzzle: Write (nearest pos points) that finds closest point by Manhattan distance."
  (make-puzzle
   :id :nearest-point
   :title "nearest"
   :description "Write (nearest pos points) that returns the point from points
closest to pos by Manhattan distance. Points are (row col) pairs.
Return the first point if there's a tie."
   :signature "(nearest pos points)"
   :hint "Track best-point and best-distance while walking the list."
   :difficulty 2
   :test-cases
   (list
    (make-test-case :input "(nearest '(0 0) '((1 0) (2 2) (0 3)))"
                    :expected (cons 1 (cons 0 wardlisp-nil))
                    :description "closest by Manhattan distance")
    (make-test-case :input "(nearest '(3 3) '((0 0) (3 4) (5 5)))"
                    :expected (cons 3 (cons 4 wardlisp-nil))
                    :description "non-origin reference point")
    (make-test-case :input "(nearest '(0 0) '((1 0)))"
                    :expected (cons 1 (cons 0 wardlisp-nil))
                    :description "single point in list"))))
