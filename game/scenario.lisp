;;;; game/scenario.lisp --- Predefined arena scenarios.

(defpackage #:recurya/game/scenario
  (:use #:cl)
  (:import-from #:recurya/game/arena
                #:make-arena-state
                #:make-grid
                #:grid-set!)
  (:export #:default-scenario))

(in-package #:recurya/game/scenario)

(defun default-scenario ()
  "Create the default 7x7 arena scenario.
Layout:
  B . . . . . .
  . # . . # . .
  . . r . . r .
  . . . # . . .
  . r . . . r .
  . . # . . # .
  . . . . . . E
Where B=bot, E=enemy, #=wall, r=resource, .=empty"
  (let ((grid (make-grid 7 7)))
    ;; Walls
    (grid-set! grid 1 1 :wall)
    (grid-set! grid 1 4 :wall)
    (grid-set! grid 3 3 :wall)
    (grid-set! grid 5 2 :wall)
    (grid-set! grid 5 5 :wall)
    ;; Resources
    (grid-set! grid 2 2 :resource)
    (grid-set! grid 2 5 :resource)
    (grid-set! grid 4 1 :resource)
    (grid-set! grid 4 5 :resource)
    (make-arena-state
     :grid grid
     :bot-pos (cons 0 0)
     :enemy-pos (cons 6 6)
     :bot-score 0
     :enemy-score 0
     :turn 0
     :max-turns 20)))
