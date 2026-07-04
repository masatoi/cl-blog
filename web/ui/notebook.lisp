;;;; web/ui/notebook.lisp --- Notebook page and cell result HTMX fragment.

(defpackage #:recurya/web/ui/notebook
  (:use #:cl)
  (:import-from #:spinneret #:with-html-string #:with-html)
  (:import-from #:alexandria #:when-let*)
  (:import-from #:recurya/game/notebook
                #:notebook-id
                #:notebook-chapter
                #:notebook-title
                #:notebook-summary
                #:notebook-cells
                #:cell-id
                #:cell-kind
                #:cell-body
                #:cell-description
                #:cell-gated-p
                #:notebook-cell-result-cell-id
                #:notebook-cell-result-kind
                #:notebook-cell-result-status
                #:notebook-cell-result-value
                #:notebook-cell-result-print-output
                #:notebook-cell-result-error-message
                #:notebook-cell-result-error-cell-id
                #:notebook-cell-result-metrics
                #:notebook-cell-result-test-results)
  (:import-from #:recurya/game/notebook-parser #:render-cell-prose-html)
  (:import-from #:recurya/web/ui/layout #:header #:header-styles)
  (:import-from #:recurya/web/ui/editor #:editor-head-tags #:editor-textarea)
  (:import-from #:recurya/web/ui/csrf #:csrf-form-block #:csrf-input)
  (:import-from #:recurya/game/novel/eval #:eval-scene)
  (:import-from #:recurya/game/novel/interpreter #:interpret-directives)
  (:import-from #:recurya/web/ui/novel #:render-player)
  (:export #:render #:render-cell-result #:render-solution-oob-reveals))

(in-package #:recurya/web/ui/notebook)

(defparameter *saved-codes* nil
  "Alist (cell-id-string . code-string) of DB-saved code, or nil for anonymous.")

(defparameter *passed-cells* nil
  "List of cell-id strings the current user has passed, or nil for anonymous.")

(defparameter *user* nil
  "Current user plist (with :id, :name, etc.), or nil for anonymous.")

(defparameter *run-cell-base* nil
  "URL prefix used to build run-cell HTMX endpoints for the cell currently
being rendered. Set by `render'. The full URL is
\"<base>/cells/<index>/run\".")

(defparameter *cells* nil
  "All cells of the notebook currently being rendered, so a solution cell can
look back for its preceding exercise. Bound in RENDER.")

(defparameter *styles*
  "body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
         margin: 0; background: #0f172a; color: #e2e8f0; line-height: 1.6; }
main { max-width: 900px; margin: 0 auto; padding: 2rem 1.5rem; flex: 1; min-width: 0; }
.layout { display: flex; align-items: flex-start; }
.sidebar { width: 260px; flex-shrink: 0; background: #0a0f1a;
           border-right: 1px solid #1e293b; padding: 1.5rem 1rem;
           overflow-y: auto; max-height: 100vh; position: sticky; top: 0;
           font-size: 0.85rem; }
.sidebar-home { display: block; color: #38bdf8; font-weight: 700;
                margin-bottom: 1rem; text-decoration: none; font-size: 0.95rem; }
.sb-chapter { margin-bottom: 0.5rem; border: 1px solid #1e293b;
              border-radius: 6px; padding: 0.4rem 0.6rem; }
.sb-chapter[open] { background: #0f172a; }
.sb-summary { color: #f8fafc; font-weight: 600; cursor: pointer;
              font-size: 0.88rem; padding: 0.2rem 0; }
.sb-summary:hover { color: #38bdf8; }
.sb-section { margin: 0.4rem 0 0.6rem 0; }
.sb-section-title { color: #94a3b8; font-size: 0.75rem; font-weight: 600;
                    margin: 0.5rem 0 0.25rem 0; }
.sb-list { list-style: none; padding: 0; margin: 0; }
.sb-list li { margin: 0; }
.sb-link { display: block; padding: 0.2rem 0.5rem; color: #94a3b8;
           text-decoration: none; font-size: 0.8rem; border-radius: 4px;
           line-height: 1.35; }
.sb-link:hover { background: #1e293b; color: #e2e8f0; }
.sb-link.active { background: #1e3a8a; color: #f8fafc; font-weight: 600; }
@media (max-width: 768px) {
  .layout { display: block; }
  .sidebar { width: auto; max-height: none; position: static;
             border-right: none; border-bottom: 1px solid #1e293b; }
}
.breadcrumb { color: #64748b; font-size: 0.9rem; margin-bottom: 1rem; }
.breadcrumb a { color: #38bdf8; text-decoration: none; }
h1 { font-size: 1.6rem; letter-spacing: -0.02em; color: #f8fafc; }
.summary { color: #94a3b8; margin-bottom: 2rem; }
.cell { margin-bottom: 1.75rem; }
.cell--prose { background: #111827; border-left: 3px solid #334155;
               padding: 1rem 1.25rem; border-radius: 0 8px 8px 0; }
.cell--code { background: #1e293b; border-radius: 10px; padding: 1rem; }
.cell--exercise { border: 1px solid #f59e0b; }
.cell__desc { color: #fbbf24; font-size: 0.95rem; line-height: 1.65;
              margin-bottom: 0.75rem; white-space: normal;
              padding: 0.5rem 0.75rem; background: rgba(251,191,36,0.07);
              border-radius: 6px; border-left: 3px solid #f59e0b; }
.cell__desc p { margin: 0 0 0.4rem 0; }
.cell__desc p:last-child { margin-bottom: 0; }
.notebook-code { width:100%; background:#0f172a; color:#e2e8f0;
                 border:1px solid #334155; border-radius:6px;
                 font-family:'SF Mono',monospace; padding:0.5rem;
                 min-height: 4rem; box-sizing: border-box; }
.btn-run { background: #2563eb; color: #fff; border: none;
           padding: 0.55rem 1.25rem; border-radius: 8px;
           font-weight: 600; cursor: pointer; font-size: 0.9rem;
           margin-top: 0.5rem; }
.btn-run:hover { background: #1d4ed8; }
.btn-run.htmx-request { opacity: 0.7; cursor: wait; }
.btn-reset { background: none; color: #94a3b8; border: 1px solid #334155;
             padding: 0.4rem 0.9rem; border-radius: 8px; font-size: 0.8rem;
             cursor: pointer; margin-top: 0.5rem; margin-left: 0.4rem; }
.btn-reset:hover { color: #f8fafc; border-color: #64748b; }
.error-hint { color: #fbbf24; font-size: 0.8rem; margin-top: 0.4rem;
              padding: 0.3rem 0.6rem; background: #1e293b;
              border-left: 3px solid #f59e0b; border-radius: 0 4px 4px 0; }
.result-panel { min-height: 1.5rem; margin-top: 0.75rem; }
.result-ok { color: #4ade80; font-family: monospace; }
.result-fail { color: #f87171; font-family: monospace; }
.result-error { color: #f87171; background: #2d1b1b;
                padding: 0.5rem 0.75rem; border-radius: 6px;
                font-family: monospace; font-size: 0.85rem;
                white-space: pre-wrap; }
.result-line { padding: 0.25rem 0; font-size: 0.9rem; }
.test-list { list-style: none; padding: 0; margin: 0.5rem 0 0 0; }
.metrics { color: #64748b; font-size: 0.8rem; margin-top: 0.5rem; }
.badge-pass { background: #16a34a; color: white;
              padding: 0.15rem 0.6rem; border-radius: 999px;
              font-size: 0.75rem; }
.print-output { background:#0f172a; padding:0.5rem;
                border-radius: 4px; color: #94a3b8;
                font-family: monospace; font-size: 0.85rem;
                white-space: pre-wrap; margin-top: 0.5rem; }
.cell--solution { }
.solution-details { background:#111827; border:1px solid #334155;
                    border-radius:8px; padding:0.5rem 0.75rem; }
.solution-details > summary { cursor:pointer; color:#38bdf8; font-weight:600;
                              font-size:0.9rem; }
.solution-body { margin:0.5rem 0 0 0; color:#e2e8f0;
                 font-family:'SF Mono',monospace; font-size:0.85rem;
                 white-space:pre-wrap; }
.solution-locked { color:#64748b; font-size:0.85rem; padding:0.5rem 0.75rem;
                   border:1px dashed #334155; border-radius:8px; }")

(defun notebook-url-id (notebook)
  "Lowercase id of the notebook, for use in URLs.
Accepts both keyword (legacy SICP) and string (UUID) ids."
  (let ((id (notebook-id notebook)))
    (string-downcase (if (keywordp id) (symbol-name id) (string id)))))

(defun %cell-id->string (id)
  "Stringify a cell or notebook id, accepting both keyword (legacy SICP)
and string (UUID) representations. NIL becomes \"\"."
  (cond ((null id) "")
        ((keywordp id) (string-downcase (symbol-name id)))
        ((symbolp id) (string-downcase (symbol-name id)))
        (t (string id))))

(defun render-course-sidebar (course-title course-slug course-handle
                              notebooks current-id)
  "Render a flat-list left sidebar for a generic course.
COURSE-TITLE, COURSE-SLUG, and COURSE-HANDLE, when all non-nil, render
a course header link pointing at /c/@<handle>/<slug>. NOTEBOOKS is a
list of plists with keys :slug :title :author-handle (and optionally
:position) in the desired display order. Each list item links to
/@<author-handle>/<slug>, with ?course=<course-slug> appended when
COURSE-SLUG is non-nil so that clicking a sidebar entry keeps the reader
inside the course view (matching the course page and prev/next links)
instead of dropping to the stand-alone notebook page. Notebooks without
an :author-handle render the title as plain text.
CURRENT-ID is the slug (or url id) of the active notebook used to mark
the matching entry as 'sb-link active'."
  (with-html
    (:aside :class "sidebar"
            (when (and course-title course-slug course-handle)
              (:a :class "sidebar-home"
                  :href (format nil "/c/@~A/~A"
                                course-handle course-slug)
                  (format nil "📘 ~A" course-title)))
            (:ul :class "sb-list"
                 (dolist (nb notebooks)
                   (let ((slug (getf nb :slug))
                         (title (getf nb :title))
                         (author-handle (getf nb :author-handle)))
                     (:li
                      (if (and slug author-handle)
                          (:a :href (if course-slug
                                        (format nil "/@~A/~A?course=~A"
                                                author-handle slug course-slug)
                                        (format nil "/@~A/~A"
                                                author-handle slug))
                              :class (if (and current-id
                                              (string= slug current-id))
                                         "sb-link active"
                                         "sb-link")
                              title)
                          (:span :class "sb-link" title)))))))))

(defun render-prose-tree (tree)
  "Render a Spinneret DSL list at runtime to an HTML string."
  (with-html-string (spinneret:interpret-html-tree tree)))

(defun render-prose-cell (cell)
  (let ((body (cell-body cell)))
    (with-html
      (:div :class "cell cell--prose"
            (cond
              ((stringp body)
               (:raw (recurya/game/notebook-parser:render-cell-prose-html body)))
              (t
               (:raw (render-prose-tree body)))))
      (:input :type "hidden" :class "notebook-code" :name "codes[]" :value ""))))

(defun render-code-cell (cell index nb-id exercise-p)
  (declare (ignore nb-id))
  (let* ((result-id (format nil "cell-~D-result" index))
         (id-suffix (format nil "-~D" index))
         (cid-str (%cell-id->string (cell-id cell)))
         (saved
           (and *saved-codes*
                (cdr (assoc cid-str *saved-codes* :test #'string=))))
         (original-code (or (cell-body cell) ""))
         (initial-code (or saved original-code ""))
         (passed-p
           (and exercise-p (member cid-str *passed-cells* :test #'string=)))
         (run-url (format nil "~A/cells/~D/run" (or *run-cell-base* "") index)))
    (with-html
      (:div :class
            (if exercise-p
                "cell cell--code cell--exercise"
                "cell cell--code")
            :data-cell-id cid-str :data-original-code original-code
            :data-textarea-id (format nil "editor-source~A" id-suffix)
            (when exercise-p
          (:div :class "cell__desc"
           (:raw (render-cell-prose-html (or (cell-description cell) "")))))
            (when passed-p (:span :class "badge-pass" "✓ done"))
            (:raw
             (editor-textarea "codes[]" initial-code :id-suffix id-suffix
                              :textarea-class "notebook-code"))
            (:button :type "button" :class "btn-run"
                     :hx-post run-url
                     :hx-target (format nil "#~A" result-id)
                     :hx-include ".notebook-code, #csrf-form"
                     :hx-swap "innerHTML"
                     "Run")
            (:button :type "button" :class "btn-reset"
                     :title "セルを初期コードに戻す"
                     "リセット")
            (:div :class "result-panel" :id result-id)))))

(defun render-scene-cell (cell index)
  "Render a :scene cell as an inline novel player. Evaluates the (self-contained)
scene with no flags and flattens it to beats. Any evaluation error is shown
inline so a bad scene never breaks the page."
  (handler-case
      (let* ((dirs (eval-scene (or (cell-body cell) "") :flags nil))
             (beats (interpret-directives dirs))
             (player (render-player :title "" :beats beats
                                    :id (format nil "cell-~D" index))))
        (with-html (:div :class "cell" (:raw player))))
    (error (e)
      (with-html
        (:div :class "cell cell--prose"
          (:p "（このシーンを表示できません: " (princ-to-string e) "）"))))))

(defun preceding-exercise-passed-p (index)
  "True when the nearest :code-exercise cell before INDEX in *cells* has been
passed (its cell-id is in *passed-cells*). NIL when there is no preceding
exercise."
  (loop for i from (1- index) downto 0
        for c = (nth i *cells*)
        when (eq (cell-kind c) :code-exercise)
          do (return (and (member (%cell-id->string (cell-id c)) *passed-cells*
                                   :test #'string=)
                          t))
        finally (return nil)))

(defun %render-solution-unlocked (cell index &key oob)
  "Render the unlocked (revealed) DOM for a :code-solution CELL at INDEX: the
container <div id=\"cell-<index>-solution\"> wrapping a collapsible <details>
with the solution body, followed by the empty hidden codes[] placeholder.
When OOB is true the container additionally carries hx-swap-oob=\"true\" so
an HTMX response can splice it into the live page out-of-band -- used to
reveal a gated solution the instant its preceding exercise is passed. Shared
by RENDER-SOLUTION-CELL (initial page render) and RENDER-SOLUTION-OOB-REVEALS
(post-Run reveal) so both emit the exact same unlocked DOM shape."
  (let ((container-id (format nil "cell-~D-solution" index)))
    (with-html
      (:div :id container-id :class "cell cell--solution"
            :hx-swap-oob (when oob "true")
        (:details :class "solution-details"
          (:summary "解答を見る")
          (:pre :class "solution-body" (or (cell-body cell) ""))))
      (unless oob
        (:input :type "hidden" :class "notebook-code" :name "codes[]"
                :value "")))))

(defun render-solution-cell (cell index)
  "Render a :code-solution cell. A non-gated solution is always shown in a
collapsible <details>. A gated solution shows its body only when its preceding
exercise is passed; otherwise only a locked placeholder (the body is never
emitted). Always emits the empty hidden codes[] placeholder for index
alignment. The container id cell-<index>-solution is the HTMX OOB target."
  (let ((unlocked (or (not (cell-gated-p cell))
                      (preceding-exercise-passed-p index))))
    (if unlocked
        (%render-solution-unlocked cell index)
        (let ((container-id (format nil "cell-~D-solution" index)))
          (with-html
            (:div :id container-id :class "cell cell--solution"
              (:div :class "solution-locked"
                "🔒 直前の演習に正解すると解答が表示されます"))
            (:input :type "hidden" :class "notebook-code" :name "codes[]"
                    :value ""))))))

(defun render-solution-oob-reveals (cells exercise-index)
  "Return HTML (string) of out-of-band <div id=\"cell-<M>-solution\"
hx-swap-oob=\"true\"> reveals for every gated :code-solution cell that belongs
to the exercise at EXERCISE-INDEX (appears after it, before the next
exercise). Empty string when there are none. Appended to a Run response after
a :pass so the solution unlocks instantly."
  (with-html-string
    (loop for i from (1+ exercise-index) below (length cells)
          for c = (nth i cells)
          until (eq (cell-kind c) :code-exercise)
          when (and (eq (cell-kind c) :code-solution) (cell-gated-p c))
            do (%render-solution-unlocked c i :oob t))))

(defun render-cell (cell index nb-id)
  (declare (ignorable cell index nb-id))
  (ecase (cell-kind cell)
    (:prose (render-prose-cell cell))
    (:scene (render-scene-cell cell index))
    (:code-eval (render-code-cell cell index nb-id nil))
    (:code-exercise (render-code-cell cell index nb-id t))
    (:code-solution (render-solution-cell cell index))))

(defun render (notebook
               &key user saved-codes passed-cells
                    (sidebar-notebooks nil) run-cell-base
                    course-title course-slug course-handle
                    breadcrumb course-prev-url course-next-url
                    current-slug
                    noindex)
  "Render the full notebook page as a complete HTML document.
USER is the logged-in user plist or nil.
SAVED-CODES is an alist (cell-id-string . code-string) of DB-saved code.
PASSED-CELLS is a list of cell-id strings this user has passed.
SIDEBAR-NOTEBOOKS controls the left TOC:
  NIL (default) - omits the sidebar entirely (used for stand-alone
    user-authored notebooks at /n/:slug without a course context).
    The legacy SICP T path was removed when the hard-coded SICP
    notebook registry was deleted; SICP is now served via the
    DB-backed course/notebook model.
  LIST - a list of notebook plists (:slug :title ...) to render via
    render-course-sidebar. COURSE-TITLE and COURSE-SLUG, when both are
    supplied, add a course header link at the top of the sidebar.
COURSE-TITLE / COURSE-SLUG are used only when SIDEBAR-NOTEBOOKS is a list.
CURRENT-SLUG, when SIDEBAR-NOTEBOOKS is a list, is the slug of the
notebook being viewed; its matching sidebar entry is marked active.
RUN-CELL-BASE is the URL prefix for run-cell HTMX endpoints. Defaults
to the SICP route /wardlisp/learn/<id> when omitted.
BREADCRUMB, when non-nil, is a list of plists overriding the default
chapter-based breadcrumb. Each entry has the shape
  (:text \"label\" :href nil-or-url)
and entries are joined by \" > \". Plain-text entries (no :href) render
as a bare span; entries with :href render as an <a>.
COURSE-PREV-URL / COURSE-NEXT-URL, when non-nil, render \"← Previous\"
and \"Next →\" links in the breadcrumb area for navigating between
notebooks within the same course."
  (let* ((*saved-codes* saved-codes)
         (*passed-cells* passed-cells)
         (*user* user)
         (*cells* (notebook-cells notebook))
         (*run-cell-base*
          (or run-cell-base
              (format nil "/wardlisp/learn/~A" (notebook-url-id notebook)))))
    (with-html-string (:doctype)
      (:html
       (:head
        (:meta :charset "utf-8")
        (:meta :name "viewport"
               :content "width=device-width, initial-scale=1")
        (:title (notebook-title notebook))
        (when noindex (:meta :name "robots" :content "noindex"))
        (:style (:raw (header-styles)))
        (:style (:raw *styles*))
        (:script :src "https://unpkg.com/htmx.org@2.0.4"
                 :integrity
                 "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
                 :crossorigin "anonymous")
        (:raw (editor-head-tags)))
       (:body :data-notebook-id (notebook-url-id notebook)
              :data-logged-in (if *user* "true" "false")
              (:raw (header user))
              (:div :class "layout"
                    (cond
                      ((null sidebar-notebooks) nil)
                      ((listp sidebar-notebooks)
                       (render-course-sidebar course-title course-slug
                                              course-handle
                                              sidebar-notebooks
                                              current-slug)))
                    (:main
                     (cond
                       (breadcrumb
                        (:div :class "breadcrumb"
                              (loop for entry in breadcrumb
                                    for first-p = t then nil
                                    do (unless first-p (:raw " > "))
                                       (let ((text (getf entry :text))
                                             (href (getf entry :href)))
                                         (if href
                                             (:a :href href text)
                                             (:span text))))))
                       (t nil))
                     (when (or course-prev-url course-next-url)
                       (:div :class "course-nav"
                             :style "margin-bottom: 1rem; font-size: 0.9rem;"
                             (when course-prev-url
                               (:a :href course-prev-url
                                   :style "color: #38bdf8; text-decoration: none; margin-right: 1rem;"
                                   "← Previous"))
                             (when course-next-url
                               (:a :href course-next-url
                                   :style "color: #38bdf8; text-decoration: none;"
                                   "Next →"))))
                     (:h1 (notebook-title notebook))
                     (:p :class "summary" (notebook-summary notebook))
                     (loop for cell in (notebook-cells notebook)
                           for i from 0
                           do (render-cell cell i (notebook-url-id notebook)))))
              (:script :src "/static/js/learn.js"))))))

(defun render-test-results (results)
  (spinneret:with-html
    (:ul :class "test-list"
         (dolist (tr results)
           (:li :class "result-line"
                (if (getf tr :passed)
                    (:span :class "result-ok" "✓")
                    (:span :class "result-fail" "✗"))
                " "
                (:code (getf tr :input))
                " — expected "
                (:code (getf tr :expected))
                " got "
                (:code (or (getf tr :actual) "<error>")))))))

(defun render-cell-result (result)
  "Render one cell's result as an HTMX fragment (no html/head wrappers).
Appends a subtle metrics line reporting the computational resources the
run consumed (fuel/steps, cons, depth) whenever the result carries
metrics, mirroring the WardLisp playground."
  (with-html-string
    ;; Normalize :limit-exceeded to :error for rendering: both surface to
    ;; the user as an error message, and Spinneret's HTML walker mangles
    ;; hyphenated keywords in case/ecase clauses (treats them as custom
    ;; elements), so we flatten to plain keywords before dispatching.
    (let ((raw-status (notebook-cell-result-status result)))
      (let ((status (if (eq raw-status :limit-exceeded) :error raw-status)))
        (ecase status
          (:ok
           (:div :class "result-ok"
                 (:code "=> " (notebook-cell-result-value result))))
          (:pass
           (:div :class "result-ok" (:span :class "badge-pass" "PASS") " 全テスト合格")
           (render-test-results (notebook-cell-result-test-results result)))
          (:fail
           (:div :class "result-fail" "一部のテストが失敗しました")
           (render-test-results (notebook-cell-result-test-results result)))
          (:error
           (let ((origin (notebook-cell-result-error-cell-id result)))
             (:pre :class "result-error"
                   (if origin
                       (format nil "セル「~A」でエラー: ~A"
                               (%cell-id->string origin)
                               (notebook-cell-result-error-message result))
                       (notebook-cell-result-error-message result)))
             (:div :class "error-hint"
                   (if origin
                       "💡 上のセル「リセット」ボタンで初期コードに戻せます。"
                       "💡 上のセルを編集している場合、「リセット」ボタンで初期コードに戻せます。")))))))
    (let ((out (notebook-cell-result-print-output result)))
      (when (and out (plusp (length out))) (:pre :class "print-output" out)))
    (let ((m (notebook-cell-result-metrics result)))
      (when m
        (:div :class "metrics"
              (format nil "Fuel: ~D | Cons: ~D | Depth: ~D"
                      (or (getf m :steps-used) 0)
                      (or (getf m :cons-allocated) 0)
                      (or (getf m :max-depth-reached) 0)))))))
