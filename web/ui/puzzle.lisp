;;;; web/ui/puzzle.lisp --- Puzzle page with code editor and result display.

(defpackage #:recurya/web/ui/puzzle
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/game/puzzle
                #:puzzle-id
                #:puzzle-title
                #:puzzle-description
                #:puzzle-signature
                #:puzzle-hint
                #:puzzle-test-cases
                #:puzzle-difficulty
                #:test-case-input
                #:test-case-description
                #:puzzle-result-passed
                #:puzzle-result-failed
                #:puzzle-result-total
                #:puzzle-result-test-results
                #:puzzle-result-fuel-used
                #:puzzle-result-cons-used
                #:puzzle-result-depth-reached
                #:puzzle-result-error
                #:test-result-passed-p
                #:test-result-expected
                #:test-result-actual
                #:test-result-description
                #:test-result-error)
  (:import-from #:wardlisp
                #:print-value)
  (:import-from #:recurya/web/ui/editor
                #:editor-head-tags
                #:editor-textarea)
  (:export #:render
           #:render-result))

(in-package #:recurya/web/ui/puzzle)

(defparameter *styles*
  "body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
         margin: 0; background: #0f172a; color: #e2e8f0; line-height: 1.6; }
main { max-width: 900px; margin: 0 auto; padding: 2rem 1.5rem; }
a { color: #38bdf8; }
h1 { font-size: 1.5rem; letter-spacing: -0.02em; color: #f8fafc; }
.breadcrumb { color: #64748b; font-size: 0.9rem; margin-bottom: 1rem; }
.breadcrumb a { color: #38bdf8; text-decoration: none; }
.puzzle-desc { color: #94a3b8; margin-bottom: 1.5rem; white-space: pre-line; }
.signature { font-family: monospace; font-size: 1.1rem; color: #38bdf8;
             background: #1e293b; padding: 0.5rem 1rem; border-radius: 8px;
             margin-bottom: 1rem; display: inline-block; }
.hint { background: #1e293b; border-left: 3px solid #f59e0b; padding: 0.75rem 1rem;
        border-radius: 0 8px 8px 0; color: #fbbf24; font-size: 0.9rem;
        margin-bottom: 1.5rem; }
.editor-area { display: flex; flex-direction: column; gap: 0.75rem; margin-bottom: 1.5rem; }
.btn-run { background: #2563eb; color: #fff; border: none; padding: 0.65rem 1.5rem;
           border-radius: 8px; font-weight: 600; cursor: pointer; font-size: 0.95rem; }
.btn-run:hover { background: #1d4ed8; }
.btn-run.htmx-request { opacity: 0.7; cursor: wait; }
.test-cases { background: #1e293b; border-radius: 8px; padding: 1rem; margin-bottom: 1.5rem; }
.test-cases h3 { margin: 0 0 0.75rem; font-size: 0.95rem; color: #94a3b8; }
.test-case { font-family: monospace; font-size: 0.9rem; color: #cbd5e1;
             padding: 0.3rem 0; }
#result-panel { min-height: 2rem; }
.result { background: #1e293b; border-radius: 8px; padding: 1.25rem; }
.result-header { font-weight: 700; font-size: 1.1rem; margin-bottom: 1rem; }
.result-pass { color: #4ade80; }
.result-fail { color: #f87171; }
.result-error { color: #f87171; background: #2d1b1b; padding: 0.75rem 1rem;
                border-radius: 8px; font-family: monospace; font-size: 0.9rem;
                margin-bottom: 1rem; white-space: pre-wrap; }
.test-row { display: flex; align-items: center; gap: 0.5rem; padding: 0.4rem 0;
            font-size: 0.9rem; border-bottom: 1px solid #334155; }
.test-row:last-child { border-bottom: none; }
.test-icon { font-size: 1rem; }
.test-detail { font-family: monospace; color: #94a3b8; font-size: 0.85rem; }
.eval-output { background: #0f172a; border: 1px solid #334155; border-radius: 8px;
               padding: 0.75rem 1rem; margin-bottom: 1rem; }
.eval-output__label { color: #64748b; font-size: 0.8rem; margin-bottom: 0.3rem; }
.eval-output__value { font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.95rem;
                      color: #4ade80; white-space: pre-wrap; }
.metrics { margin-top: 1rem; color: #64748b; font-size: 0.85rem; }
")

(defun render (puzzle)
  "Render the full puzzle page with code editor."
  (let ((id (string-downcase (symbol-name (puzzle-id puzzle)))))
    (with-html-string
      (:doctype)
      (:html
       (:head (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title (format nil "~A - WardLisp" (puzzle-title puzzle)))
        (:script :src "https://unpkg.com/htmx.org@2.0.4"
         :integrity "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
         :crossorigin "anonymous")
        (:style (:raw *styles*))
        (:raw (editor-head-tags)))
       (:body
        (:main
         (:div :class "breadcrumb"
          (:a :href "/wardlisp/" "Puzzles") " / " (puzzle-title puzzle))
         (:h1 (puzzle-title puzzle))
         (:p :class "puzzle-desc" (puzzle-description puzzle))
         (:div :class "signature" (puzzle-signature puzzle))
         (when (puzzle-hint puzzle)
           (:div :class "hint" (puzzle-hint puzzle)))
         ;; Test cases preview
         (:div :class "test-cases"
          (:h3 "Test Cases")
          (dolist (tc (puzzle-test-cases puzzle))
            (:div :class "test-case"
             (format nil "~A  ; ~A" (test-case-input tc) (test-case-description tc)))))
         ;; Editor
         (:form :class "editor-area"
          (:raw (editor-textarea "code"
                                 (format nil "; ~A~%~%" (puzzle-signature puzzle))
                                 :placeholder "Write your solution here..."))
          (:button :class "btn-run" :type "button"
                   :hx-post (format nil "/wardlisp/puzzle/~A/run" id)
                   :hx-include "closest form"
                   :hx-target "#result-panel"
                   :hx-swap "innerHTML"
                   "Run"))
         ;; Result area (populated by HTMX)
         (:div :id "result-panel")))))))

(defun render-result (result &key eval-output eval-error print-output)
  "Render the puzzle result as an HTMX fragment.
EVAL-OUTPUT is the printed result of evaluating the user code standalone.
EVAL-ERROR is any error message from standalone evaluation.
PRINT-OUTPUT is the stdout from (print ...) calls during evaluation."
  (let ((passed (puzzle-result-passed result))
        (total (puzzle-result-total result))
        (error-msg (puzzle-result-error result)))
    (with-html-string
      (:div :class "result"
       ;; Show print output if any
       (when (and print-output (plusp (length print-output)))
         (:div :class "eval-output"
          (:div :class "eval-output__label" "Print Output")
          (:div :class "eval-output__value"
           :style "color: #fbbf24;" print-output)))
       ;; Show standalone evaluation result
       (when (or eval-output eval-error)
         (:div :class "eval-output"
          (:div :class "eval-output__label" "Result")
          (if eval-error
              (:div :class "result-error" eval-error)
              (:div :class "eval-output__value" eval-output))))
       ;; Test results header (always show pass/fail count)
       (:div :class
        (if (and (= passed total) (zerop (puzzle-result-failed result)))
            "result-header result-pass"
            "result-header result-fail")
        (format nil "~D / ~D passed" passed total))
       ;; Individual test rows (always show)
       (dolist (tr (puzzle-result-test-results result))
         (:div :class "test-row"
          (:span :class (if (test-result-passed-p tr)
                           "test-icon result-pass"
                           "test-icon result-fail")
           (:raw (if (test-result-passed-p tr)
                     "&#x2714;"
                     "&#x2718;")))
          (:span (test-result-description tr))
          (unless (test-result-passed-p tr)
            (if (test-result-error tr)
                (:span :class "test-detail"
                 (format nil " error: ~A" (test-result-error tr)))
                (:span :class "test-detail"
                 (format nil " expected ~A, got ~A"
                         (if (stringp (test-result-expected tr))
                             (test-result-expected tr)
                             (print-value (test-result-expected tr)))
                         (print-value (test-result-actual tr))))))))
       (:div :class "metrics"
        (format nil "Fuel: ~D | Cons: ~D | Depth: ~D"
                (puzzle-result-fuel-used result)
                (puzzle-result-cons-used result)
                (puzzle-result-depth-reached result)))))))
