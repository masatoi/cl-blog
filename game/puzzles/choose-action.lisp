;;;; game/puzzles/choose-action.lisp --- Puzzle: strategic action choice.

(defpackage #:recurya/game/puzzles/choose-action
  (:use #:cl)
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-nil)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-choose-action-puzzle))

(in-package #:recurya/game/puzzles/choose-action)

(defun make-choose-action-puzzle ()
  "Puzzle: Write (choose-action my-pos resource-pos) that returns the best
move direction to approach a resource."
  (make-puzzle
   :id :choose-action
   :title "choose-action"
   :description "Write (choose-action my-pos resource-pos) that returns the
direction keyword (:up, :down, :left, :right) to move closer to the resource.
If already at the resource, return :pickup. Prefer vertical movement when
distances are equal."
   :signature "(choose-action my-pos resource-pos)"
   :hint "Compare row and col differences. Move in the axis with larger gap, preferring vertical."
   :difficulty 3
   :test-cases
   (list
    (make-test-case :input "(choose-action '(0 0) '(3 1))" :expected :down
                    :description "target below-right, vertical larger")
    (make-test-case :input "(choose-action '(3 0) '(3 5))" :expected :right
                    :description "same row, target right")
    (make-test-case :input "(choose-action '(5 3) '(2 3))" :expected :up
                    :description "same col, target above")
    (make-test-case :input "(choose-action '(3 3) '(3 3))" :expected :pickup
                    :description "already at resource")
    (make-test-case :input "(choose-action '(3 5) '(3 2))" :expected :left
                    :description "same row, target left")
    (make-test-case :input "(choose-action '(3 3) '(1 1))" :expected :up
                    :description "target above-left, equal distance, prefer vertical"))))
