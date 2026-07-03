;;;; web/ui/notebook-form.lisp --- Create/edit form for user-authored notebooks.

(defpackage #:recurya/web/ui/notebook-form
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/layout
                #:common-styles
                #:page-shell)
  (:import-from #:recurya/web/ui/csrf
                #:csrf-input)
  (:import-from #:recurya/web/ui/editor
                #:editor-head-tags)
  (:export #:render))

(in-package #:recurya/web/ui/notebook-form)

(defparameter *form-page-styles*
  "/* User-notebook form page styles */
.nb-form { display: flex; flex-direction: column; gap: 1.25rem; }
.form-group { display: flex; flex-direction: column; gap: 0.35rem; }
.form-group label { font-weight: 600; font-size: 0.9rem; }
.form-group input,
.form-group textarea,
.form-group select { width: 100%; box-sizing: border-box; }
.form-group textarea.body-field {
  min-height: 600px;
  font-family: 'SF Mono', Menlo, Consolas, monospace;
  font-size: 0.85rem;
  white-space: pre-wrap;
  word-wrap: break-word;
}
.form-group textarea.summary-field { min-height: 80px; resize: vertical; }
.form-hint { color: var(--color-text-muted); font-size: 0.8rem; }
.form-actions { display: flex; gap: 0.75rem; margin-top: 0.5rem; }
.flash-message { padding: 0.75rem 1rem; border-radius: 6px;
                 margin-bottom: 1rem; font-size: 0.9rem; }
.flash-message.success { background: var(--color-success-bg);
                         color: var(--color-success-text); }
.flash-message.error { background: var(--color-error-bg);
                       color: var(--color-error-text); }
.cheatsheet { background: var(--color-surface, #1e293b);
              border: 1px solid var(--color-border, #334155);
              border-radius: 8px; padding: 1rem 1.25rem;
              margin-top: 1rem; font-size: 0.85rem; }
.cheatsheet h3 { margin: 0 0 0.5rem 0; font-size: 0.95rem; }
.cheatsheet pre { background: var(--color-bg, #0f172a);
                  padding: 0.75rem; border-radius: 6px;
                  overflow-x: auto; font-size: 0.8rem;
                  font-family: 'SF Mono', Menlo, Consolas, monospace; }
.error-list { list-style: none; padding: 0; margin: 0; }
.error-list li { padding: 0.25rem 0; font-size: 0.85rem; }
.error-list .line { display: inline-block; min-width: 4rem;
                    color: var(--color-text-muted);
                    font-family: monospace; }")

(defparameter *cheatsheet-text*
  "===prose===
Markdown text — **bold**, *italic*, `code`, links.

===eval===
(+ 1 2)

===exercise: 説明文===
; ユーザが穴埋めするコード

===expect: 説明文===
期待値（リテラル）

===expect===
input: (foo 1 2)
output: 3")

(defun render (&key user notebook message errors (cells-json "[]"))
  "Render the notebook create/edit form as an HTML string.

NOTEBOOK is a plist with :id :title :slug :summary :body-md :status when
editing. When NOTEBOOK is NIL, renders a new-notebook form. ERRORS is
a list of plists like (:line N :message \"...\"). CELLS-JSON is a JSON
string (array of cell objects, as produced by
`recurya/game/notebook-jsonb:cell->jsonb-form') embedded via a
data-cells attribute for the client-side cell editor to consume."
  (let* ((editing-p (not (null notebook)))
         (nb-id      (getf notebook :id))
         (nb-title   (or (getf notebook :title) ""))
         (nb-slug    (or (getf notebook :slug) ""))
         (nb-summary (or (getf notebook :summary) ""))
         (nb-body    (or (getf notebook :body-md) ""))
         (nb-status  (or (getf notebook :status) "draft"))
         (nb-visibility (or (getf notebook :visibility) "private"))
         (action-url (if editing-p
                         (format nil "/dashboard/notebooks/~A" nb-id)
                         "/dashboard/notebooks"))
         (page-title (if editing-p "Edit Notebook" "New Notebook"))
         (page-styles (concatenate 'string (common-styles) *form-page-styles*)))
    (page-shell :title (format nil "recurya - ~A" page-title)
                :styles page-styles
                :user user
                :head-extras (editor-head-tags)
                :body-scripts
                (with-html-string
                  (:script :type "module" :src "/static/js/cell-editor.js"))
                :body-content
                (with-html-string
                  (:div :class "card"
                    (:h1 page-title)
                    (when message
                      (:div :class "flash-message success" message))
                    (when errors
                      (:div :class "flash-message error"
                        (:strong "Validation errors:")
                        (:ul :class "error-list"
                          (dolist (err errors)
                            (:li
                              (:span :class "line"
                                (format nil "L~A" (or (getf err :line) "?")))
                              " "
                              (getf err :message))))))
                    (:form :class "nb-form" :method "post" :action action-url
                      (:raw (csrf-input))
                      (:div :class "form-group"
                        (:label :for "title" "Title")
                        (:input :type "text" :id "title" :name "title"
                          :value nb-title :required t
                          :placeholder "Notebook title"))
                      (:div :class "form-group"
                        (:label :for "slug" "Slug")
                        (:input :type "text" :id "slug" :name "slug"
                          :value nb-slug
                          :placeholder "auto-generated-from-title")
                        (:span :class "form-hint"
                          "Leave blank to auto-generate from title."))
                      (:div :class "form-group"
                        (:label :for "summary" "Summary")
                        (:textarea :id "summary" :name "summary"
                          :class "summary-field" :maxlength "500"
                          :placeholder "Short summary (max 500 chars)"
                          nb-summary))
                      (:div :id "cell-editor-root" :data-cells cells-json)
                      (:div :class "form-group"
                        (:label :for "body" "Body (Markdown + cell fences)")
                        (:textarea :id "body" :name "body"
                          :class "body-field" :required t :wrap "soft"
                          :placeholder "===prose===\nWrite here..."
                          nb-body))
                      (:div :class "form-group"
                        (:label :for "status" "Status")
                        (:select :id "status" :name "status"
                          (:option :value "draft"
                            :selected (when (equal nb-status "draft") "selected")
                            "Draft")
                          (:option :value "published"
                            :selected (when (equal nb-status "published") "selected")
                            "Published")))
                      (:div :class "form-group"
                        (:label :for "visibility" "Visibility")
                        (:select :id "visibility" :name "visibility"
                          (:option :value "private"
                            :selected (when (equal nb-visibility "private") "selected")
                            "Private (only you)")
                          (:option :value "unlisted"
                            :selected (when (equal nb-visibility "unlisted") "selected")
                            "Unlisted (anyone with the link)")
                          (:option :value "public"
                            :selected (when (equal nb-visibility "public") "selected")
                            "Public (anyone)")))
                      (:div :class "form-actions"
                        (:button :type "submit" :class "btn-primary"
                          (if editing-p "Update Notebook" "Create Notebook"))
                        (:a :class "btn-secondary" :href "/dashboard/notebooks"
                          :style "text-decoration:none;text-align:center"
                          "Cancel")))
                    (:div :class "cheatsheet"
                      (:h3 "セル区切りチートシート")
                      (:pre *cheatsheet-text*)))))))
