;;;; web/ui/playground.lisp --- Free-form WardLisp code evaluation page.

(defpackage #:recurya/web/ui/playground
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:wardlisp
                #:evaluate
                #:print-value)
  (:import-from #:recurya/web/ui/editor
                #:editor-head-tags
                #:editor-textarea)
  (:export #:render
           #:render-result))

(in-package #:recurya/web/ui/playground)

(defparameter *styles* "body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
         margin: 0; background: #0f172a; color: #e2e8f0; line-height: 1.6; }
main { max-width: 900px; margin: 0 auto; padding: 2rem 1.5rem; }
a { color: #38bdf8; }
h1 { font-size: 1.5rem; letter-spacing: -0.02em; color: #f8fafc; }
.breadcrumb { color: #64748b; font-size: 0.9rem; margin-bottom: 1rem; }
.breadcrumb a { color: #38bdf8; text-decoration: none; }
.description { color: #94a3b8; margin-bottom: 1.5rem; }
.editor-area { display: flex; flex-direction: column; gap: 0.75rem; margin-bottom: 1.5rem; }
.btn-run { background: #2563eb; color: #fff; border: none; padding: 0.65rem 1.5rem;
           border-radius: 8px; font-weight: 600; cursor: pointer; font-size: 0.95rem; }
.btn-run:hover { background: #1d4ed8; }
.btn-run.htmx-request { opacity: 0.7; cursor: wait; }
#output-panel { min-height: 2rem; }
.result { background: #1e293b; border-radius: 8px; padding: 1.25rem; }
.result-value { font-family: 'SF Mono', 'Fira Code', monospace; font-size: 1rem;
                color: #4ade80; white-space: pre-wrap; }
.result-error { color: #f87171; background: #2d1b1b; padding: 0.75rem 1rem;
                border-radius: 8px; font-family: monospace; font-size: 0.9rem;
                white-space: pre-wrap; }
.metrics { margin-top: 1rem; color: #64748b; font-size: 0.85rem; }
")

(defun render ()
  "Render the playground page with code editor."
  (with-html-string
    (:doctype)
    (:html
     (:head (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:title "WardLisp Playground")
      (:script :src "https://unpkg.com/htmx.org@2.0.4" :integrity
       "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
       :crossorigin "anonymous")
      (:style (:raw *styles*)) (:raw (editor-head-tags)))
     (:body
      (:main
       (:div :class "breadcrumb" (:a :href "/wardlisp/" "WardLisp") " / Playground")
       (:h1 "Playground")
       (:p :class "description"
        "Write and run any WardLisp code. Experiment freely!")
       (:form :class "editor-area"
        (:raw
         (editor-textarea "code" "(+ 1 2)"
                          :placeholder "Write WardLisp code here..."))
        (:button :class "btn-run" :type "button"
         :hx-post "/wardlisp/playground/run"
         :hx-include "closest form"
         :hx-target "#output-panel"
         :hx-swap "innerHTML"
         "Run"))
       (:div :id "output-panel"))))))

(defun render-result (code)
  "Evaluate CODE and render the result as an HTMX fragment."
  (handler-case
      (multiple-value-bind (result metrics)
          (evaluate code
                   :fuel 100000
                   :max-depth 200
                   :max-cons 10000
                   :max-output 10000
                   :max-integer 100000000000
                   :timeout 5)
        (let ((fuel-used (getf metrics :steps-used))
              (error-msg (getf metrics :error-message)))
          (with-html-string
            (:div :class "result"
             (when error-msg
               (:div :class "result-error" error-msg))
             (:div :class "result-value" (print-value result))
             (:div :class "metrics"
              (format nil "Fuel used: ~D" (or fuel-used 0)))))))
    (error (e)
      (with-html-string
        (:div :class "result"
         (:div :class "result-error" (format nil "~A" e)))))))
