;;;; tests/game/arena.lisp --- Tests for arena simulator.

(defpackage #:recurya/tests/game/arena
  (:use #:cl #:rove)
  (:import-from #:recurya/game/arena
                #:make-arena-state
                #:make-grid
                #:grid-set!
                #:grid-ref
                #:simulate-arena
                #:arena-result-frames
                #:arena-result-bot-score
                #:arena-result-enemy-score
                #:arena-result-error
                #:arena-state-bot-pos
                #:arena-state-bot-score
                #:arena-state-grid
                #:arena-state-turn)
  (:import-from #:recurya/game/scenario
                #:default-scenario))

(in-package #:recurya/tests/game/arena)

(defparameter *alist-ref-def*
  "(define (alist-ref key alist)
     (cond ((null? alist) nil)
           ((equal? key (car (car alist))) (car (cdr (car alist))))
           (t (alist-ref key (cdr alist)))))"
  "WardLisp alist-ref definition to prepend to test code that needs it.
Returns the second element (cadr) of the matched entry.")

(defun simple-arena ()
  "A minimal 3x3 arena for testing."
  (let ((grid (make-grid 3 3)))
    (grid-set! grid 1 1 :wall)
    (grid-set! grid 0 2 :resource)
    (make-arena-state
     :grid grid
     :bot-pos (cons 0 0)
     :enemy-pos (cons 2 2)
     :max-turns 5)))

(deftest bot-movement
  (testing "bot moves right"
    (let* ((result (simulate-arena
                    "(define (decide-action state) 'right)"
                    (simple-arena)))
           (frame1 (second (arena-result-frames result))))
      (ok (equal (cons 0 1) (arena-state-bot-pos frame1))))))

(deftest wall-collision
  (testing "bot stays when hitting wall"
    ;; Bot at (0,0), moves down to (1,0), then right would hit wall at (1,1)
    (let* ((arena (simple-arena))
           (result (simulate-arena
                    (format nil "~A~%(define (decide-action state)
                       (if (= (alist-ref 'turn state) 1) 'down 'right))"
                            *alist-ref-def*)
                    arena))
           (frame2 (third (arena-result-frames result))))
      ;; After turn 2: moved down to (1,0), then tried right to (1,1) wall → stays at (1,0)
      (ok (equal (cons 1 0) (arena-state-bot-pos frame2))))))

(deftest resource-pickup
  (testing "bot picks up resource"
    ;; Bot at (0,0), resource at (0,2). Move right twice, then pickup.
    (let* ((arena (simple-arena))
           (result (simulate-arena
                    (format nil "~A~%(define (decide-action state)
                       (let ((turn (alist-ref 'turn state)))
                         (if (<= turn 2) 'right 'pickup)))"
                            *alist-ref-def*)
                    arena)))
      (ok (>= (arena-result-bot-score result) 1)))))

(deftest full-simulation-completes
  (testing "simulation runs all turns"
    (let ((result (simulate-arena
                   "(define (decide-action state) 'wait)"
                   (default-scenario))))
      (ok (null (arena-result-error result)))
      (ok (= 21 (length (arena-result-frames result)))))))

(deftest fuel-exhaustion-in-arena
  (testing "infinite loop is caught during simulation"
    (let ((result (simulate-arena
                   "(define (decide-action state) (decide-action state))"
                   (simple-arena))))
      (ok (arena-result-error result)))))

(deftest determinism
  (testing "same code produces same result"
    (let* ((code "(define (decide-action state) 'right)")
           (r1 (simulate-arena code (default-scenario)))
           (r2 (simulate-arena code (default-scenario))))
      (ok (= (arena-result-bot-score r1) (arena-result-bot-score r2)))
      (ok (= (arena-result-enemy-score r1) (arena-result-enemy-score r2))))))
