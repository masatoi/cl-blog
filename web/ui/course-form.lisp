;;;; web/ui/course-form.lisp --- Create/edit form for courses.

(defpackage #:recurya/web/ui/course-form
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/layout
                #:common-styles
                #:page-shell)
  (:import-from #:recurya/web/ui/csrf
                #:csrf-input)
  (:export #:render
           #:render-course-notebooks-list))

(in-package #:recurya/web/ui/course-form)

(defparameter *form-page-styles*
  "/* Course form page styles */
.course-form { display: flex; flex-direction: column; gap: 1.25rem; }
.form-group { display: flex; flex-direction: column; gap: 0.35rem; }
.form-group label { font-weight: 600; font-size: 0.9rem; }
.form-group input,
.form-group textarea,
.form-group select { width: 100%; box-sizing: border-box; }
.form-group textarea.summary-field { min-height: 80px; resize: vertical; }
.form-hint { color: var(--color-text-muted); font-size: 0.8rem; }
.form-actions { display: flex; gap: 0.75rem; margin-top: 0.5rem; }
.flash-message { padding: 0.75rem 1rem; border-radius: 6px;
                 margin-bottom: 1rem; font-size: 0.9rem; }
.flash-message.success { background: var(--color-success-bg);
                         color: var(--color-success-text); }
.flash-message.error { background: var(--color-error-bg);
                       color: var(--color-error-text); }
.error-list { list-style: none; padding: 0; margin: 0; }
.error-list li { padding: 0.25rem 0; font-size: 0.85rem; }
.error-list .line { display: inline-block; min-width: 4rem;
                    color: var(--color-text-muted);
                    font-family: monospace; }
.course-notebooks-section { margin-top: 2rem;
                            border-top: 1px solid var(--color-border);
                            padding-top: 1.5rem; }
.course-notebooks-list { list-style: none; padding: 0; margin: 0; }
.course-notebooks-list li { display: flex; align-items: center;
                            gap: 0.5rem; padding: 0.5rem 0;
                            border-bottom: 1px solid var(--color-border); }
.course-notebooks-list .nb-title { flex: 1; }
.course-notebooks-list .nb-controls { display: flex; gap: 0.25rem; }
.course-notebooks-empty { color: var(--color-text-muted);
                          font-size: 0.9rem; padding: 0.5rem 0; }
.add-notebook-form { display: flex; gap: 0.5rem; align-items: end;
                     margin-top: 1rem; }
.add-notebook-form .form-group { flex: 1; }")

(defun render-course-notebooks-list (course course-notebooks eligible-notebooks
                                     &key message)
  "Render the notebooks-list section of the course edit form as an HTML fragment.

Returns a `<div id=\"course-notebooks-list\">` element suitable for HTMX
outerHTML swap.

Arguments:
  COURSE              - Course plist with at least :id.
  COURSE-NOTEBOOKS    - List of plists for already-attached notebooks. Each
                        plist has :id (notebook UUID), :cn-id (BIGSERIAL
                        join row id), :title, :position.
  ELIGIBLE-NOTEBOOKS  - List of plists for notebooks the user can still add.
                        Each plist has :id (notebook UUID) and :title.
  MESSAGE             - Optional flash message rendered above the list.

Each row's Up/Down/Remove buttons fire HTMX POSTs against
/dashboard/courses/<id>/notebooks/<cn-id>/{up,down,remove} and replace this entire
fragment via outerHTML swap. Re-rendering the whole list (rather than
scoping Remove to a single <li>) keeps the eligible-notebooks dropdown
in sync with the attached set after every mutation."
  (let ((course-id (getf course :id)))
    (spinneret:with-html-string
      (:div :id "course-notebooks-list"
            :class "course-notebooks-section"
            (:h2 "Notebooks")
            (when message
              (:div :class "flash-message error" message))
            (cond
              ((null course-notebooks)
               (:p :class "course-notebooks-empty"
                   "No notebooks attached yet. Add one below."))
              (t
               (:ul :class "course-notebooks-list"
                    (dolist (nb course-notebooks)
                      (let* ((cn-id (getf nb :cn-id))
                             (up-url
                              (format nil "/dashboard/courses/~A/notebooks/~A/up"
                                      course-id cn-id))
                             (down-url
                              (format nil "/dashboard/courses/~A/notebooks/~A/down"
                                      course-id cn-id))
                             (remove-url
                              (format nil "/dashboard/courses/~A/notebooks/~A/remove"
                                      course-id cn-id)))
                        (:li :data-notebook-id (getf nb :id)
                             :data-cn-id cn-id
                             (:span :class "nb-title" (getf nb :title))
                             (:span :class "nb-controls"
                                    (:button :type "button"
                                             :class "btn-secondary"
                                             :hx-post up-url
                                             :hx-target "#course-notebooks-list"
                                             :hx-swap "outerHTML"
                                             :hx-include "#csrf-form"
                                             "Up")
                                    (:button :type "button"
                                             :class "btn-secondary"
                                             :hx-post down-url
                                             :hx-target "#course-notebooks-list"
                                             :hx-swap "outerHTML"
                                             :hx-include "#csrf-form"
                                             "Down")
                                    (:button :type "button"
                                             :class "btn-secondary"
                                             :hx-post remove-url
                                             :hx-target "#course-notebooks-list"
                                             :hx-swap "outerHTML"
                                             :hx-include "#csrf-form"
                                             "Remove"))))))))
            (cond
              ((null eligible-notebooks)
               (:p :class "course-notebooks-empty"
                   "No more notebooks available to add."))
              (t
               (:form :class "add-notebook-form"
                      :hx-post (format nil "/dashboard/courses/~A/notebooks" course-id)
                      :hx-target "#course-notebooks-list"
                      :hx-swap "outerHTML"
                      :hx-include "#csrf-form"
                      (:div :class "form-group"
                            (:label :for "notebook_id" "Add notebook")
                            (:select :id "notebook_id" :name "notebook_id"
                                     :required t
                                     (dolist (nb eligible-notebooks)
                                       (:option :value (getf nb :id)
                                                (getf nb :title)))))
                      (:button :type "submit" :class "btn-primary" "Add"))))))))

(defun render (&key user course message errors course-notebooks eligible-notebooks)
  "Render the course create/edit form as an HTML string.

COURSE is a plist with :id :title :slug :summary :status when editing.
When COURSE is NIL, renders a new-course form. ERRORS is a list of
plists like (:line N :message \"...\").

When editing an existing COURSE, the caller may also supply:
  COURSE-NOTEBOOKS    - List of plists for currently attached notebooks
                        (:id :title :position).
  ELIGIBLE-NOTEBOOKS  - List of plists describing the user's other
                        published notebooks not yet attached
                        (:id :title), used as the Add dropdown source."
  (let* ((c-id      (getf course :id))
         (editing-p (not (null c-id)))
         (c-title   (or (getf course :title) ""))
         (c-slug    (or (getf course :slug) ""))
         (c-summary (or (getf course :summary) ""))
         (c-status  (or (getf course :status) "draft"))
         (c-visibility (or (getf course :visibility) "private"))
         (action-url (if editing-p
                         (format nil "/dashboard/courses/~A" c-id)
                         "/dashboard/courses"))
         (page-title (if editing-p "Edit Course" "New Course"))
         (page-styles (concatenate 'string (common-styles) *form-page-styles*)))
    (page-shell
     :title (format nil "recurya - ~A" page-title)
     :styles page-styles
     :user user
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
         (:form :class "course-form" :method "post" :action action-url
           (:raw (csrf-input))
           (:div :class "form-group"
             (:label :for "title" "Title")
             (:input :type "text" :id "title" :name "title"
               :value c-title :required t :placeholder "Course title"))
           (:div :class "form-group"
             (:label :for "slug" "Slug")
             (:input :type "text" :id "slug" :name "slug"
               :value c-slug :placeholder "auto-generated-from-title")
             (:span :class "form-hint"
               "Leave blank to auto-generate from title."))
           (:div :class "form-group"
             (:label :for "summary" "Summary")
             (:textarea :id "summary" :name "summary"
               :class "summary-field" :maxlength "500"
               :placeholder "Short summary (max 500 chars)"
               c-summary))
           (:div :class "form-group"
             (:label :for "status" "Status")
             (:select :id "status" :name "status"
               (:option :value "draft"
                 :selected (when (equal c-status "draft") "selected")
                 "Draft")
               (:option :value "published"
                 :selected (when (equal c-status "published") "selected")
                 "Published")))
           (:div :class "form-group"
             (:label :for "visibility" "Visibility")
             (:select :id "visibility" :name "visibility"
               (:option :value "private"
                 :selected (when (equal c-visibility "private") "selected")
                 "Private (only you)")
               (:option :value "unlisted"
                 :selected (when (equal c-visibility "unlisted") "selected")
                 "Unlisted (anyone with the link)")
               (:option :value "public"
                 :selected (when (equal c-visibility "public") "selected")
                 "Public (anyone)")))
           (:div :class "form-actions"
             (:button :type "submit" :class "btn-primary"
               (if editing-p "Update Course" "Create Course"))
             (:a :class "btn-secondary" :href "/dashboard/courses"
               :style "text-decoration:none;text-align:center"
               "Cancel")))
         (when editing-p
           (:raw (render-course-notebooks-list
                  course course-notebooks eligible-notebooks))))))))
