;;;; game/puzzles/registry.lisp --- Central puzzle registry.

(defpackage #:recurya/game/puzzles/registry
  (:use #:cl)
  (:import-from #:recurya/game/puzzles/adjacent #:make-adjacent-puzzle)
  (:import-from #:recurya/game/puzzles/contains #:make-contains-puzzle)
  (:import-from #:recurya/game/puzzles/nearest-point #:make-nearest-point-puzzle)
  (:import-from #:recurya/game/puzzles/safe-moves #:make-safe-moves-puzzle)
  (:import-from #:recurya/game/puzzles/choose-action #:make-choose-action-puzzle)
  (:import-from #:recurya/game/puzzle #:puzzle-id)
  (:export #:get-puzzle
           #:all-puzzles))

(in-package #:recurya/game/puzzles/registry)

(defparameter *puzzles*
  (list (make-adjacent-puzzle)
        (make-contains-puzzle)
        (make-nearest-point-puzzle)
        (make-safe-moves-puzzle)
        (make-choose-action-puzzle))
  "All available puzzles, in display order.")

(defun get-puzzle (id)
  "Find puzzle by keyword ID. Returns puzzle struct or NIL."
  (find id *puzzles* :key #'puzzle-id))

(defun all-puzzles ()
  "Return list of all puzzles in display order."
  *puzzles*)
