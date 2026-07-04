;;;; game/notebook.lisp --- Notebook/cell model and run-cell evaluator.

(defpackage #:recurya/game/notebook
  (:use #:cl)
  (:import-from #:wardlisp
                #:evaluate
                #:print-value)
  (:import-from #:recurya/game/puzzle
                #:make-test-case
                #:test-case-input
                #:test-case-expected
                #:test-case-description)
  (:export #:notebook #:make-notebook
           #:notebook-id #:notebook-chapter #:notebook-title
           #:notebook-summary #:notebook-cells
           #:cell #:make-cell
           #:cell-id #:cell-kind #:cell-body
           #:cell-description #:cell-test-cases #:cell-gated-p
           #:notebook-cell-result #:make-notebook-cell-result
           #:notebook-cell-result-cell-id
           #:notebook-cell-result-kind
           #:notebook-cell-result-status
           #:notebook-cell-result-value
           #:notebook-cell-result-print-output
           #:notebook-cell-result-error-message
           #:notebook-cell-result-error-cell-id
           #:notebook-cell-result-metrics
           #:notebook-cell-result-test-results
           #:run-cell
           #:*notebook-fuel* #:*notebook-max-cons*
           #:*notebook-max-depth* #:*notebook-max-output*
           #:*notebook-timeout*))

(in-package #:recurya/game/notebook)

(defstruct notebook
  "A SICP-style notebook: a list of cells rendered top-down."
  (id nil :type (or null keyword string))
  (chapter "" :type string)
  (title "" :type string)
  (summary "" :type string)
  (cells nil :type list))

(defstruct cell
  "A single notebook cell. KIND is one of :prose, :code-eval, :code-exercise,
   :code-solution, :scene. BODY is a Spinneret DSL list for :prose cells, or a
   source string for code cells. GATED-P (only meaningful for :code-solution)
   hides the solution until the preceding exercise is passed."
  (id nil :type (or null keyword string))
  (kind nil :type keyword)
  body               ; untyped: list for prose, string for code cells
  (description "" :type string)
  (test-cases nil :type list)
  (gated-p nil :type boolean))

(defstruct notebook-cell-result
  "Result of running one cell."
  (cell-id nil :type (or null keyword string))
  (kind nil :type keyword)
  (status nil :type keyword)
  value
  (print-output "" :type string)
  (error-message nil :type (or null string))
  (error-cell-id nil :type (or null keyword string))
  (metrics nil :type list)
  (test-results nil :type list))

(defparameter *notebook-fuel* 20000
  "Default fuel limit for a notebook cell evaluation.")

(defparameter *notebook-max-cons* 10000
  "Default cons allocation limit for a notebook cell evaluation.")

(defparameter *notebook-max-depth* 200
  "Default call-stack depth limit for a notebook cell evaluation.")

(defparameter *notebook-max-output* 4096
  "Default captured-output byte limit for a notebook cell evaluation.")

(defparameter *notebook-timeout* 5
  "Default wall-clock timeout (seconds) for a notebook cell evaluation.")

(defun %extract-error-line (msg)
  "Extract 1-based line number from error messages like '... at L:C ...'.
   Returns NIL if no such pattern is present (typical for runtime errors
   such as recursion-limit or step-limit-exceeded)."
  (when (stringp msg)
    (let ((pos (search "at " msg)))
      (when pos
        (let* ((start (+ pos 3))
               (end (or (position #\: msg :start start :end (length msg))
                        (length msg)))
               (digits (subseq msg start end)))
          (when (and (plusp (length digits))
                     (every #'digit-char-p digits))
            (parse-integer digits)))))))

(defun %line-to-cell-index (line codes)
  "Map 1-based LINE within concatenated CODES (joined by single newlines)
   to a 0-based cell index, or NIL if the line is out of range."
  (when (and (integerp line) (plusp line) codes)
    (let ((current-line 1))
      (loop for code in codes
            for idx from 0
            for end-line = (+ current-line (count #\Newline code))
            when (<= current-line line end-line)
              do (return-from %line-to-cell-index idx)
            do (setf current-line (+ end-line 1)))
      nil)))

(defun %attribute-error-to-cell (msg upstream-cells upstream-codes)
  "Given an error MSG and the upstream CELLS + their submitted CODES,
   return the cell-id (keyword) of the cell where the error originates,
   or NIL when the message lacks line info or the line is out of range."
  (let ((line (%extract-error-line msg)))
    (when line
      (let ((idx (%line-to-cell-index line upstream-codes)))
        (when (and idx (< idx (length upstream-cells)))
          (cell-id (nth idx upstream-cells)))))))

(defun run-cell (notebook cell-index submitted-codes)
  "Execute the cell at CELL-INDEX in NOTEBOOK.
   For :code-eval cells, concatenate SUBMITTED-CODES[0..CELL-INDEX] and
   evaluate once. For :code-exercise cells, additionally run each
   test-case by appending its input. Returns a NOTEBOOK-CELL-RESULT.
   Signals an error for :prose cells and out-of-range indices."
  (let* ((cells (notebook-cells notebook))
         (cell (nth cell-index cells)))
    (unless cell
      (error "Cell index ~A out of range for notebook ~A"
             cell-index (notebook-id notebook)))
    (when (eq (cell-kind cell) :prose)
      (error "Cannot run a prose cell (id=~A)" (cell-id cell)))
    (let* ((take (min (1+ cell-index) (length submitted-codes)))
           (codes (subseq submitted-codes 0 take))
           (cells-prefix (subseq cells 0 take))
           (combined (format nil "~{~A~^~%~}" codes)))
      (if (eq (cell-kind cell) :code-exercise)
          (run-exercise-cell cell cells-prefix codes combined)
          (run-eval-cell cell cells-prefix codes combined)))))

(defun run-eval-cell (cell cells-prefix codes-prefix combined)
  "Evaluate COMBINED as a :code-eval cell, returning a cell result.
   On error, attribute the failure to the offending cell when the wardlisp
   error message includes line info (typical for parse errors)."
  (multiple-value-bind (result metrics)
      (evaluate combined
                :fuel *notebook-fuel* :max-cons *notebook-max-cons*
                :max-depth *notebook-max-depth* :max-output *notebook-max-output*
                :timeout *notebook-timeout*)
    (let ((err (getf metrics :error-message)))
      (if err
          (make-notebook-cell-result
           :cell-id (cell-id cell) :kind (cell-kind cell)
           :status :error :value nil
           :print-output (or (getf metrics :output) "")
           :error-message err
           :error-cell-id (%attribute-error-to-cell err cells-prefix codes-prefix)
           :metrics metrics :test-results nil)
          (make-notebook-cell-result
           :cell-id (cell-id cell) :kind (cell-kind cell)
           :status :ok :value (print-value result)
           :print-output (or (getf metrics :output) "")
           :error-message nil :metrics metrics :test-results nil)))))

(defun run-exercise-cell (cell cells-prefix codes-prefix combined)
  "Grade a :code-exercise cell against its TEST-CASES.
   Returns a NOTEBOOK-CELL-RESULT with status :pass, :fail, or :error.
   On user-code error, attribute the failure to the offending cell when
   the wardlisp error message includes line info."
  (multiple-value-bind (user-result user-metrics)
      (evaluate combined
                :fuel *notebook-fuel* :max-cons *notebook-max-cons*
                :max-depth *notebook-max-depth* :max-output *notebook-max-output*
                :timeout *notebook-timeout*)
    (declare (ignore user-result))
    (let ((user-error (getf user-metrics :error-message)))
      (if user-error
          (make-notebook-cell-result
           :cell-id (cell-id cell) :kind :code-exercise
           :status :error :value nil
           :print-output (or (getf user-metrics :output) "")
           :error-message user-error
           :error-cell-id (%attribute-error-to-cell user-error cells-prefix codes-prefix)
           :metrics user-metrics
           :test-results nil)
          (let ((test-results nil)
                (all-pass t))
            (dolist (tc (cell-test-cases cell))
              (let ((full-code (format nil "~A~%~A" combined (test-case-input tc))))
                (multiple-value-bind (result metrics)
                    (evaluate full-code
                              :fuel *notebook-fuel* :max-cons *notebook-max-cons*
                              :max-depth *notebook-max-depth*
                              :max-output *notebook-max-output*
                              :timeout *notebook-timeout*)
                  (let* ((terr (getf metrics :error-message))
                         (expected-str (test-case-expected tc))
                         (actual-str (unless terr (print-value result)))
                         (passed (and (not terr)
                                      (string= actual-str expected-str))))
                    (unless passed (setf all-pass nil))
                    (push (list :input (test-case-input tc)
                                :description (test-case-description tc)
                                :expected expected-str
                                :actual actual-str
                                :passed passed
                                :error terr)
                          test-results)))))
            (make-notebook-cell-result
             :cell-id (cell-id cell) :kind :code-exercise
             :status (if all-pass :pass :fail)
             :value nil
             :print-output (or (getf user-metrics :output) "")
             :error-message nil
             :metrics user-metrics
             :test-results (nreverse test-results)))))))
