;;;; game/puzzles/sqrt2-newton.lisp --- Puzzle: approximate √2 with Newton's method.

(defpackage #:recurya/game/puzzles/sqrt2-newton
  (:use #:cl)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-sqrt2-newton-puzzle))

(in-package #:recurya/game/puzzles/sqrt2-newton)

(defun make-sqrt2-newton-puzzle ()
  "Puzzle: Approximate √2 using Newton's method."
  (make-puzzle
   :id :sqrt2-newton
   :title "sqrt2-newton"
   :description "Write (sqrt2-newton n) that approximates the square root of 2
using Newton's method with n iterations, starting from 1.0.
Each step improves the guess x by computing (x + 2/x) / 2."
   :signature "(sqrt2-newton n)"
   :hint "Define an inner helper (improve x) that returns (/ (+ x (/ 2 x)) 2), then loop n times from 1.0."
   :difficulty 2
   :test-cases
   (list
    (make-test-case :input "(sqrt2-newton 0)" :expected "1.0"
                    :description "zero iterations returns initial guess")
    (make-test-case :input "(sqrt2-newton 1)" :expected "1.5"
                    :description "one iteration")
    (make-test-case :input "(sqrt2-newton 3)" :expected "1.4142156862745097"
                    :description "three iterations")
    (make-test-case :input "(sqrt2-newton 5)" :expected "1.414213562373095"
                    :description "five iterations (close to exact)")
    (make-test-case :input "(sqrt2-newton 10)" :expected "1.414213562373095"
                    :description "ten iterations (converged)"))))
