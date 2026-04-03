;;;; game/puzzles/safe-moves.lisp --- Puzzle: filter safe moves on a grid.

(defpackage #:recurya/game/puzzles/safe-moves
  (:use #:cl)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-safe-moves-puzzle))

(in-package #:recurya/game/puzzles/safe-moves)

(defun make-safe-moves-puzzle ()
  "Puzzle: Write (safe-move? pos dir walls grid-size) to check if a move is valid."
  (make-puzzle
   :id :safe-moves
   :title "safe-move?"
   :description "Write (safe-move? pos dir walls grid-size) that returns t if moving
from pos in direction dir stays within the grid (0 to grid-size-1) and
doesn't land on a wall. pos is (row col), dir is 'up/'down/'left/'right,
walls is a list of (row col) pairs."
   :signature "(safe-move? pos dir walls grid-size)"
   :hint "Compute new position from direction, then check bounds and wall membership. Use equal? to compare direction symbols."
   :difficulty 2
   :test-cases
   (list
    (make-test-case :input "(safe-move? '(0 0) 'right '() 7)" :expected t
                    :description "move right from origin, no walls")
    (make-test-case :input "(safe-move? '(0 0) 'up '() 7)" :expected nil
                    :description "move up from row 0 is out of bounds")
    (make-test-case :input "(safe-move? '(0 0) 'left '() 7)" :expected nil
                    :description "move left from col 0 is out of bounds")
    (make-test-case :input "(safe-move? '(3 3) 'down '((4 3)) 7)" :expected nil
                    :description "move into wall")
    (make-test-case :input "(safe-move? '(6 6) 'down '() 7)" :expected nil
                    :description "move down from last row is out of bounds")
    (make-test-case :input "(safe-move? '(3 3) 'up '((1 1) (5 5)) 7)" :expected t
                    :description "move up, walls elsewhere"))))
