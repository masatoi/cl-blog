;;;; game/notebook-parser.lisp --- Markdown <-> cell list parser for user notebooks.

(defpackage #:recurya/game/notebook-parser
  (:use #:cl)
  (:import-from #:recurya/game/notebook
                #:make-cell
                #:cell-id
                #:cell-kind
                #:cell-body
                #:cell-description
                #:cell-test-cases
                #:cell-gated-p)
  (:import-from #:recurya/game/puzzle
                #:make-test-case
                #:test-case-input
                #:test-case-expected
                #:test-case-description)
  (:import-from #:uuid #:make-v4-uuid)
  (:import-from #:recurya/utils/html-sanitize #:sanitize-html)
  (:export #:parse-notebook-body #:cells->body-md #:render-cell-prose-html))

(in-package #:recurya/game/notebook-parser)

(defun split-lines (s)
  "Split S into a list of lines (stripping a single trailing \\r if any)."
  (let ((lines '())
        (start 0))
    (loop for i from 0 below (length s)
          when (char= (char s i) #\Newline)
            do (let ((line (subseq s start i)))
                 (push (if (and (> (length line) 0)
                                (char= (char line (1- (length line))) #\Return))
                           (subseq line 0 (1- (length line)))
                           line)
                       lines)
                 (setf start (1+ i))))
    (when (< start (length s))
      (push (subseq s start) lines))
    (nreverse lines)))

(defparameter +exercise-header-regex+
  (cl-ppcre:create-scanner "^===exercise: (.+)===$")
  "Scanner for `===exercise: <description>===' fence headers.")

(defparameter +solution-header-regex+
  (cl-ppcre:create-scanner "^===solution: (.+)===$")
  "Scanner for `===solution: <description>===' fence headers.")

(defparameter +solution-locked-header-regex+
  (cl-ppcre:create-scanner "^===solution-locked: (.+)===$")
  "Scanner for `===solution-locked: <description>===' fence headers, marking a
   gated solution (revealed only after the preceding exercise is passed).")

(defparameter +expect-header-regex+
  (cl-ppcre:create-scanner "^===expect(?:: (.+))?===$")
  "Scanner for `===expect===' and `===expect: <description>===' fence headers.
   The optional capture group holds the description, or NIL when absent.")

(defparameter +bare-exercise-header-regex+
  (cl-ppcre:create-scanner "^===exercise===$")
  "Scanner for `===exercise===' (no description). Triggers a validation
   error: an exercise header must include a description.")

(defparameter +generic-header-regex+
  (cl-ppcre:create-scanner "^===.+===$")
  "Scanner for any line that looks like a fence header (`===...==='),
   used to detect unknown headers after specific patterns failed.")

(defun parse-fence-header (line)
  "If LINE is a fence header line, return (values KIND DESCRIPTION-OR-NIL GATED-P).
   Otherwise return (values NIL NIL NIL).

   Recognised KINDs:
     :prose          for `===prose==='
     :code-eval      for `===eval==='
     :scene          for `===scene==='
     :code-exercise  for `===exercise: <desc>==='
     :code-solution  for `===solution: <desc>==='         (GATED-P nil)
                     and `===solution-locked: <desc>==='   (GATED-P t)
     :expect         for `===expect===' and `===expect: <desc>==='
                     (sentinel kind: not stored as a cell, used by the
                      state machine in parse-notebook-body to attach a
                      test-case to the pending exercise cell)

   DESCRIPTION is the captured description string, or NIL when no
   description is present in the header. GATED-P is T only for the
   solution-locked variant; NIL otherwise."
  (cond
    ((string= line "===prose===") (values :prose nil nil))
    ((string= line "===eval===")  (values :code-eval nil nil))
    ((string= line "===scene===") (values :scene nil nil))
    (t
     (multiple-value-bind (m groups)
         (cl-ppcre:scan-to-strings +exercise-header-regex+ line)
       (when m
         (return-from parse-fence-header
           (values :code-exercise (aref groups 0) nil))))
     (multiple-value-bind (m groups)
         (cl-ppcre:scan-to-strings +solution-locked-header-regex+ line)
       (when m
         (return-from parse-fence-header
           (values :code-solution (aref groups 0) t))))
     (multiple-value-bind (m groups)
         (cl-ppcre:scan-to-strings +solution-header-regex+ line)
       (when m
         (return-from parse-fence-header
           (values :code-solution (aref groups 0) nil))))
     (multiple-value-bind (m groups)
         (cl-ppcre:scan-to-strings +expect-header-regex+ line)
       (when m
         (return-from parse-fence-header
           (values :expect (aref groups 0) nil))))
     (values nil nil nil))))

(defun parse-expect-block (body description)
  "Parse the buffered text BODY of a single `===expect===' block into a
   test-case struct.

   Two forms are supported:
     - input/output form: lines `input: <expr>' and `output: <value>'
       (in either order). When any `input:' line is present this form
       is used; the captured input/output strings are passed to
       MAKE-TEST-CASE as :input and :expected.
     - one-line form: a single non-empty trimmed line is treated as the
       expected output, with :input set to the empty string.

   DESCRIPTION is the description string carried on the test-case
   (typically NIL or empty when absent). When NIL, an empty string is
   stored on the struct."
  (let* ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) body))
         (lines (remove-if (lambda (l) (zerop (length l)))
                           (split-lines trimmed)))
         (input-line (find-if (lambda (l)
                                (and (>= (length l) 6)
                                     (string= (subseq l 0 6) "input:")))
                              lines))
         (output-line (find-if (lambda (l)
                                 (and (>= (length l) 7)
                                      (string= (subseq l 0 7) "output:")))
                               lines))
         (desc (or description "")))
    (cond
      (input-line
       ;; input/output form: extract substrings after the prefix and trim.
       (let ((input (string-trim '(#\Space #\Tab)
                                 (subseq input-line 6)))
             (output (if output-line
                         (string-trim '(#\Space #\Tab)
                                      (subseq output-line 7))
                         "")))
         (make-test-case :input input
                         :expected output
                         :description desc)))
      (t
       ;; one-line form: treat the trimmed body as the expected output.
       (make-test-case :input ""
                       :expected trimmed
                       :description desc)))))

(defun take-matching-cell-id (kind body description existing-cells)
  "Walk EXISTING-CELLS once. If we find a cell whose (KIND BODY DESCRIPTION)
   triple matches, capture its ID and exclude it from the returned list.
   Matching uses EQ on KIND and STRING= on BODY/DESCRIPTION (with NIL
   coerced to the empty string).

   Returns (values MATCHED-ID-OR-NIL REMAINING-LIST). Only the first
   matching cell is consumed; later matches in EXISTING-CELLS remain in
   REMAINING-LIST so two new cells with the same triple do not both reuse
   the same ID."
  (let ((matched-id nil)
        (remaining 'nil))
    (dolist (c existing-cells)
      (cond
        ((and (null matched-id)
              (eq (cell-kind c) kind)
              (string= (or (cell-body c) "") (or body ""))
              (string= (or (cell-description c) "") (or description "")))
         (setf matched-id (cell-id c)))
        (t (push c remaining))))
    (values matched-id (nreverse remaining))))

(defun parse-notebook-body (body-md &optional existing-cells)
  "Parse BODY-MD into (values CELLS ERRORS).

   BODY-MD is a string using `===KIND===' fence lines to delimit cells.
   Supported fences:
     ===prose===
     ===eval===
     ===exercise: <description>===
     ===expect===
     ===expect: <description>===

   Each parsed cell receives a string UUID as its ID, unless a cell in
   EXISTING-CELLS matches by (KIND BODY DESCRIPTION) — in that case the
   existing cell's ID is reused so that learner progress (keyed by
   cell-id) survives notebook edits. Matching is first-fit and
   consume-on-match: each existing cell can be reused at most once.

   ERRORS is a list of plists (:line N :message \"...\") where N is the
   1-based line number of the offending input. The following validation
   errors are emitted:

     * `===expect===' or `===expect: <desc>===' with no preceding
       `===exercise===' cell.
     * Bare `===exercise===' header without a description.
     * Unknown fence header (anything that looks like `===...===' but
       does not match a recognised kind).
     * The body contains no cell at all (empty/whitespace-only input,
       or input consisting only of unknown / stray headers).

   State machine:
     * CURRENT-KIND / CURRENT-DESC / CURRENT-BUFFER hold the cell that is
       currently being collected (prose, eval, or exercise body).
     * PENDING-EXERCISE-CELL is non-NIL while collecting test-cases for
       an exercise. When the exercise body is closed (by encountering an
       :expect header), the cell struct is constructed and held here so
       successive ===expect=== blocks can append test-cases.
     * IN-EXPECT-P + EXPECT-DESC + EXPECT-BUFFER track the currently
       collected expect block, finalised on the next non-expect header
       or EOF.

   Test-cases accumulate on PENDING-EXERCISE-CELL via APPEND so they are
   stored in source order. The exercise cell is flushed to CELLS only
   when the next non-expect header arrives (or EOF)."
  (let ((errors '())
        (cells '())
        (current-kind nil)
        (current-desc nil)
        (current-gated-p nil)
        (current-buffer (make-array 0 :element-type 'character
                                      :fill-pointer 0 :adjustable t))
        (pending-exercise-cell nil)
        (in-expect-p nil)
        (expect-desc nil)
        (expect-buffer (make-array 0 :element-type 'character
                                     :fill-pointer 0 :adjustable t))
        (lines (split-lines body-md))
        (line-number 0)
        (remaining-existing (copy-list existing-cells)))
    (labels ((buffer-string (buf)
               (string-trim '(#\Space #\Tab #\Newline #\Return)
                            (coerce buf 'string)))
             (append-line-to (buf line)
               (vector-push-extend #\Newline buf)
               (loop for c across line do (vector-push-extend c buf)))
             (push-error (line-no message)
               (push (list :line line-no :message message) errors))
             (finalise-expect ()
               ;; Convert the buffered expect block into a test-case and
               ;; append it to the pending exercise cell. If there is no
               ;; pending exercise the block is dropped (the stray-expect
               ;; error was emitted at the header line).
               (when in-expect-p
                 (when pending-exercise-cell
                   (let ((tc (parse-expect-block
                              (coerce expect-buffer 'string)
                              expect-desc)))
                     (setf (cell-test-cases pending-exercise-cell)
                           (append (cell-test-cases pending-exercise-cell)
                                   (list tc)))))
                 (setf (fill-pointer expect-buffer) 0
                       expect-desc nil
                       in-expect-p nil)))
             (close-exercise-body ()
               ;; Convert the currently-collected exercise body+desc into
               ;; a struct held in pending-exercise-cell, ready to receive
               ;; test-cases from following ===expect=== blocks.
               (when (eq current-kind :code-exercise)
                 (let ((body (buffer-string current-buffer))
                       (desc (or current-desc "")))
                   (multiple-value-bind (matched-id new-remaining)
                       (take-matching-cell-id :code-exercise body desc
                                              remaining-existing)
                     (setf remaining-existing new-remaining)
                     (setf pending-exercise-cell
                           (make-cell :id (or matched-id
                                              (princ-to-string (uuid:make-v4-uuid)))
                                      :kind :code-exercise
                                      :body body
                                      :description desc
                                      :test-cases nil))))
                 (setf (fill-pointer current-buffer) 0
                       current-kind nil
                       current-desc nil
                       current-gated-p nil)))
             (flush-pending-exercise ()
               (when pending-exercise-cell
                 (push pending-exercise-cell cells)
                 (setf pending-exercise-cell nil)))
             (flush-current ()
               ;; Flush a non-exercise cell (prose / eval) into CELLS.
               (when current-kind
                 (let ((body (buffer-string current-buffer))
                       (desc (or current-desc "")))
                   (multiple-value-bind (matched-id new-remaining)
                       (take-matching-cell-id current-kind body desc
                                              remaining-existing)
                     (setf remaining-existing new-remaining)
                     (push (make-cell :id (or matched-id
                                              (princ-to-string (uuid:make-v4-uuid)))
                                      :kind current-kind
                                      :body body
                                      :description desc
                                      :gated-p current-gated-p)
                           cells)))
                 (setf (fill-pointer current-buffer) 0
                       current-kind nil
                       current-desc nil
                       current-gated-p nil))))
      (dolist (line lines)
        (incf line-number)
        (multiple-value-bind (kind desc gated) (parse-fence-header line)
          (cond
            ;; ===expect=== or ===expect: <desc>===
            ((eq kind :expect)
             (cond
               ;; No exercise to attach to: emit error and drop the block.
               ((and (null pending-exercise-cell)
                     (not (eq current-kind :code-exercise)))
                (push-error line-number
                            "===expect=== without preceding ===exercise===")
                ;; Drop any in-progress expect (also stray) so subsequent
                ;; body lines are not mis-attached.
                (setf in-expect-p nil
                      expect-desc nil
                      (fill-pointer expect-buffer) 0))
               (t
                ;; Closing expect of any in-progress expect block.
                (finalise-expect)
                ;; If we were collecting an exercise body, freeze it now.
                (when (eq current-kind :code-exercise)
                  (close-exercise-body))
                ;; Begin a new expect block.
                (setf in-expect-p t
                      expect-desc desc
                      (fill-pointer expect-buffer) 0))))
            ;; Any other recognised header.
            (kind
             ;; First close any open expect block.
             (finalise-expect)
             ;; Flush the pending exercise (with its accumulated tests).
             (flush-pending-exercise)
             ;; Flush any open prose/eval cell.
             (flush-current)
             (setf current-kind kind
                   current-desc desc
                   current-gated-p gated))
            ;; Bare ===exercise=== without description.
            ((cl-ppcre:scan +bare-exercise-header-regex+ line)
             (push-error line-number
                         "===exercise=== requires a description (===exercise: <desc>===)"))
            ;; Looks like a header but matched nothing known.
            ((cl-ppcre:scan +generic-header-regex+ line)
             (push-error line-number
                         (format nil "Unknown header: ~A" line)))
            ;; Body line: append to the active buffer.
            (t
             (cond
               (in-expect-p
                (append-line-to expect-buffer line))
               (current-kind
                (append-line-to current-buffer line)))))))
      ;; EOF cleanup, in order: close expect, flush pending exercise,
      ;; flush plain cell.
      (finalise-expect)
      (flush-pending-exercise)
      (flush-current))
    (let ((final-cells (nreverse cells)))
      (when (null final-cells)
        (push (list :line 1 :message "Notebook contains no cell") errors))
      (values final-cells (nreverse errors)))))

(defun render-cell (stream cell)
  "Render one CELL to STREAM, header + body, no trailing newline.

   For :code-exercise cells, each test-case is appended after the
   exercise body separated by a single blank line."
  (let ((kind (cell-kind cell))
        (body (or (cell-body cell) ""))
        (desc (or (cell-description cell) "")))
    (ecase kind
      (:prose         (write-string "===prose===" stream))
      (:code-eval     (write-string "===eval===" stream))
      (:scene         (write-string "===scene===" stream))
      (:code-exercise (format stream "===exercise: ~A===" desc))
      (:code-solution
       (if (cell-gated-p cell)
           (format stream "===solution-locked: ~A===" desc)
           (format stream "===solution: ~A===" desc))))
    (write-char #\Newline stream)
    (write-string body stream)
    (when (eq kind :code-exercise)
      (dolist (tc (cell-test-cases cell))
        (write-char #\Newline stream)
        (write-char #\Newline stream)
        (render-test-case stream tc)))))

(defun render-test-case (stream tc)
  "Render one TEST-CASE TC to STREAM as `===expect[: <desc>]===' header
   followed by either a `input: <i>\\noutput: <o>' two-line form (when
   TEST-CASE-INPUT is non-empty) or just the expected value on a single
   line. No trailing newline is emitted after the body."
  (let ((desc (or (test-case-description tc) ""))
        (input (or (test-case-input tc) ""))
        (expected (or (test-case-expected tc) "")))
    (if (zerop (length desc))
        (write-string "===expect===" stream)
        (format stream "===expect: ~A===" desc))
    (write-char #\Newline stream)
    (cond
      ((plusp (length input))
       (format stream "input: ~A~%output: ~A" input expected))
      (t
       (write-string expected stream)))))

(defun cells->body-md (cells)
  "Render CELLS list back into the canonical body-md string.

   The result, when re-parsed by PARSE-NOTEBOOK-BODY, yields cells equal
   in (KIND BODY DESCRIPTION TEST-CASES) to the input. Cells are
   separated by exactly one blank line; no trailing newline is emitted.

   Output format per cell kind:
     :prose          -> `===prose===\\n<body>'
     :code-eval      -> `===eval===\\n<body>'
     :code-exercise  -> `===exercise: <description>===\\n<body>'
                        followed, for each test-case, by
                          `===expect[: <description>]===\\n<expect-body>'
     :code-solution  -> `===solution: <description>===\\n<body>'
                        (or `===solution-locked: <description>===\\n<body>'
                        when CELL-GATED-P is true)

   Test-case body uses two-line `input: <i>\\noutput: <o>' form when
   TEST-CASE-INPUT is non-empty; otherwise the single-line expected
   value is emitted directly."
  (with-output-to-string (s)
    (loop for cell in cells
          for first-p = t then nil
          do (unless first-p
               (write-char #\Newline s)
               (write-char #\Newline s))
             (render-cell s cell))))

(defun render-cell-prose-html (markdown-string)
  "Convert MARKDOWN-STRING to HTML via 3bmd, then run it through the HTML
allowlist sanitizer. Used to render `prose' cell bodies for display."
  (sanitize-html
   (with-output-to-string (s)
     (3bmd:parse-string-and-print-to-stream markdown-string s))))
