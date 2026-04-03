;;;; game/arena.lisp --- Arena simulator for bot vs bot competition.
;;;;
;;;; Manages a 7x7 grid where a user-controlled bot competes against
;;;; a greedy enemy bot to collect resources over 20 turns.

(defpackage #:recurya/game/arena
  (:use #:cl)
  (:import-from #:wardlisp
                #:evaluate)
  (:export #:arena-state
           #:make-arena-state
           #:arena-state-grid
           #:arena-state-bot-pos
           #:arena-state-enemy-pos
           #:arena-state-bot-score
           #:arena-state-enemy-score
           #:arena-state-turn
           #:arena-state-max-turns
           #:arena-state-output
           #:simulate-arena
           #:arena-result
           #:arena-result-frames
           #:arena-result-bot-score
           #:arena-result-enemy-score
           #:arena-result-fuel-used
           #:arena-result-error
           #:make-grid
           #:grid-set!
           #:grid-ref))

(in-package #:recurya/game/arena)

;;; --- Data Structures ---

(defstruct arena-state
  "State of the arena at a given turn."
  (grid nil)           ; 7x7 2D simple-array of keywords
  (bot-pos '(0 . 0))  ; (row . col)
  (enemy-pos '(6 . 6)) ; (row . col)
  (bot-score 0 :type fixnum)
  (enemy-score 0 :type fixnum)
  (turn 0 :type fixnum)
  (max-turns 20 :type fixnum)
  (output nil))

(defstruct arena-result
  "Result of a complete arena simulation."
  (frames nil :type list)     ; list of arena-state snapshots
  (bot-score 0 :type fixnum)
  (enemy-score 0 :type fixnum)
  (fuel-used 0 :type fixnum)
  (error nil))

(defparameter *arena-fuel* 5000 "Fuel limit per turn for arena evaluation.")

(defparameter *arena-max-cons* 2000 "Cons limit per turn for arena evaluation.")

(defparameter *arena-max-depth* 50 "Depth limit per turn for arena evaluation.")

(defparameter *arena-max-output* 1024 "Output limit per turn for arena evaluation.")

(defparameter *arena-timeout* 5 "Timeout in seconds per turn for arena evaluation.")

(defparameter *valid-action-strings* '("up" "down" "left" "right" "wait" "pickup")
  "Valid action names as strings (WardLisp symbols are CL strings).")

;;; --- Grid Operations ---

(defun make-grid (rows cols &optional (default :empty))
  "Create a rows x cols grid filled with DEFAULT."
  (let ((grid (make-array (list rows cols) :initial-element default)))
    grid))

(defun grid-ref (grid row col)
  "Get cell value at (row, col)."
  (aref grid row col))

(defun grid-set! (grid row col value)
  "Set cell value at (row, col)."
  (setf (aref grid row col) value))

(defun grid-rows (grid) (array-dimension grid 0))
(defun grid-cols (grid) (array-dimension grid 1))

(defun in-bounds-p (grid row col)
  "Return T if (row, col) is within grid bounds."
  (and (>= row 0) (< row (grid-rows grid))
       (>= col 0) (< col (grid-cols grid))))

(defun wall-p (grid row col)
  "Return T if (row, col) is a wall or out of bounds."
  (or (not (in-bounds-p grid row col))
      (eq :wall (grid-ref grid row col))))

(defun copy-grid (grid)
  "Return a fresh copy of the grid."
  (let* ((rows (grid-rows grid))
         (cols (grid-cols grid))
         (new (make-grid rows cols)))
    (dotimes (r rows)
      (dotimes (c cols)
        (grid-set! new r c (grid-ref grid r c))))
    new))

;;; --- Movement ---

(defun action->delta (action)
  "Return (drow . dcol) for an action, or NIL for non-movement."
  (case action
    (:up '(-1 . 0))
    (:down '(1 . 0))
    (:left '(0 . -1))
    (:right '(0 . 1))
    (t nil)))

(defun apply-move (grid pos action)
  "Apply a movement action. Returns new (row . col) position.
If move is invalid (wall/OOB), returns original position."
  (let ((delta (action->delta action)))
    (if (null delta)
        pos
        (let ((new-row (+ (car pos) (car delta)))
              (new-col (+ (cdr pos) (cdr delta))))
          (if (wall-p grid new-row new-col)
              pos
              (cons new-row new-col))))))

;;; --- Pickup ---

(defun try-pickup (grid pos)
  "Try to pick up a resource at POS. Returns (scored-p . new-grid)."
  (let ((row (car pos))
        (col (cdr pos)))
    (if (and (in-bounds-p grid row col)
             (eq :resource (grid-ref grid row col)))
        (progn
          (grid-set! grid row col :empty)
          t)
        nil)))

;;; --- Enemy AI ---

(defun manhattan-distance (p1 p2)
  "Manhattan distance between two (row . col) positions."
  (+ (abs (- (car p1) (car p2)))
     (abs (- (cdr p1) (cdr p2)))))

(defun find-resources (grid)
  "Return list of (row . col) positions containing resources."
  (let ((resources nil))
    (dotimes (r (grid-rows grid))
      (dotimes (c (grid-cols grid))
        (when (eq :resource (grid-ref grid r c))
          (push (cons r c) resources))))
    (nreverse resources)))

(defun nearest-resource (pos grid)
  "Find the nearest resource to POS. Returns (row . col) or NIL."
  (let ((resources (find-resources grid))
        (best nil)
        (best-dist most-positive-fixnum))
    (dolist (r resources)
      (let ((d (manhattan-distance pos r)))
        (when (< d best-dist)
          (setf best r best-dist d))))
    best))

(defun enemy-decide-action (enemy-pos grid)
  "Greedy enemy: move toward nearest resource, or :wait if none."
  (let ((target (nearest-resource enemy-pos grid)))
    (if (null target)
        :wait
        (let ((dr (- (car target) (car enemy-pos)))
              (dc (- (cdr target) (cdr enemy-pos))))
          ;; Move in the direction with larger delta, preferring vertical
          (cond
            ((and (= dr 0) (= dc 0)) :pickup)
            ((>= (abs dr) (abs dc))
             (if (> dr 0) :down :up))
            (t
             (if (> dc 0) :right :left)))))))

;;; --- State Conversion to WardLisp ---

(defun state->wardlisp-source (state)
  "Generate WardLisp source code that defines `state` as an alist.
Keys are plain symbols (no colon prefix) since external wardlisp
does not support CL keywords. Positions are wrapped in sublists.
All values are accessed via (alist-ref 'key state) using cadr pattern."
  (format nil "(define state '((my-pos (~A ~A)) (enemy-pos (~A ~A)) (my-score ~A) (enemy-score ~A) (turn ~A) (max-turns ~A)))"
          (car (arena-state-bot-pos state))
          (cdr (arena-state-bot-pos state))
          (car (arena-state-enemy-pos state))
          (cdr (arena-state-enemy-pos state))
          (arena-state-bot-score state)
          (arena-state-enemy-score state)
          (arena-state-turn state)
          (arena-state-max-turns state)))

;;; --- Simulation ---

(defun copy-state (state)
  "Deep copy an arena state."
  (make-arena-state
   :grid (copy-grid (arena-state-grid state))
   :bot-pos (arena-state-bot-pos state)
   :enemy-pos (arena-state-enemy-pos state)
   :bot-score (arena-state-bot-score state)
   :enemy-score (arena-state-enemy-score state)
   :turn (arena-state-turn state)
   :max-turns (arena-state-max-turns state)
   :output (arena-state-output state)))

(defun parse-action (value)
  "Convert a WardLisp value to an action keyword. Returns :wait for invalid.
External wardlisp returns symbols as CL strings, so we map string values
to CL keywords for the arena engine."
  (if (stringp value)
      (let ((action (find value *valid-action-strings* :test #'string-equal)))
        (if action
            (intern (string-upcase action) :keyword)
            :wait))
      :wait))

(defun simulate-arena (user-code initial-state)
  "Run a full arena simulation. Returns an arena-result."
  (let ((state (copy-state initial-state))
        (frames nil)
        (total-fuel 0))
    ;; Record initial frame
    (push (copy-state state) frames)
    (handler-case
        (progn
          (dotimes (turn-num (arena-state-max-turns state))
            (setf (arena-state-turn state) (1+ turn-num))
            ;; Get bot action from user code
            (let* ((state-source (state->wardlisp-source state))
                   (full-code (format nil "~A~%~A~%(decide-action state)"
                                      user-code state-source)))
              (multiple-value-bind (result metrics)
                  (evaluate full-code
                            :fuel *arena-fuel*
                            :max-cons *arena-max-cons*
                            :max-depth *arena-max-depth*
                            :max-output *arena-max-output*
                            :timeout *arena-timeout*)
                (incf total-fuel (or (getf metrics :steps-used) 0))
            (let ((output (getf metrics :output)))
              (when (and output (plusp (length output)))
                (setf (arena-state-output state) output)))
                (when (getf metrics :error-message)
                  (return-from simulate-arena
                    (make-arena-result
                     :frames (nreverse frames)
                     :bot-score (arena-state-bot-score state)
                     :enemy-score (arena-state-enemy-score state)
                     :fuel-used total-fuel
                     :error (format nil "Turn ~D: ~A"
                                    (arena-state-turn state)
                                    (getf metrics :error-message)))))
                (let ((bot-action (parse-action result))
                      (enemy-action (enemy-decide-action
                                     (arena-state-enemy-pos state)
                                     (arena-state-grid state))))
                  ;; Apply bot movement
                  (unless (eq bot-action :pickup)
                    (setf (arena-state-bot-pos state)
                          (apply-move (arena-state-grid state)
                                      (arena-state-bot-pos state) bot-action)))
                  ;; Apply enemy movement
                  (unless (eq enemy-action :pickup)
                    (setf (arena-state-enemy-pos state)
                          (apply-move (arena-state-grid state)
                                      (arena-state-enemy-pos state) enemy-action)))
                  ;; Bot pickup first (priority)
                  (when (eq bot-action :pickup)
                    (when (try-pickup (arena-state-grid state)
                                      (arena-state-bot-pos state))
                      (incf (arena-state-bot-score state))))
                  ;; Enemy pickup second
                  (when (eq enemy-action :pickup)
                    (when (try-pickup (arena-state-grid state)
                                      (arena-state-enemy-pos state))
                      (incf (arena-state-enemy-score state))))
                  ;; Record frame
                  (push (copy-state state) frames)))))
          ;; Simulation complete
          (make-arena-result
           :frames (nreverse frames)
           :bot-score (arena-state-bot-score state)
           :enemy-score (arena-state-enemy-score state)
           :fuel-used total-fuel))
      (error (e)
        (make-arena-result
         :frames (nreverse frames)
         :bot-score (arena-state-bot-score state)
         :enemy-score (arena-state-enemy-score state)
         :fuel-used total-fuel
         :error (format nil "Simulation error: ~A" e))))))
