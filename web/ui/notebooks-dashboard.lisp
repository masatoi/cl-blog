;;;; web/ui/notebooks-dashboard.lisp --- Admin notebook list page with HTMX interactions.

(defpackage #:recurya/web/ui/notebooks-dashboard
  (:use #:cl)
  (:import-from #:spinneret #:with-html-string)
  (:import-from #:recurya/web/i18n/core
                #:tr)
  (:import-from #:recurya/web/ui/layout
                #:common-styles
                #:format-timestamp
                #:page-shell
                #:icon)
  (:export #:render
           #:render-notebook-state-dropdown))

(in-package #:recurya/web/ui/notebooks-dashboard)

(defparameter *page-styles*
  "/* User-notebooks admin page styles */
.actions-bar { display: flex; justify-content: flex-end; margin-bottom: 1rem; }
.new-nb-btn {
  display: inline-flex; align-items: center; gap: 0.4rem;
  padding: 0.5rem 1.2rem; border: none; border-radius: 6px;
  background: var(--color-primary); color: #fff;
  font-weight: 500; font-size: 0.85rem; cursor: pointer;
  text-decoration: none; transition: background 0.15s ease;
}
.new-nb-btn:hover { background: var(--color-primary-hover);
                    color: #fff; text-decoration: none; }
.status-pill { cursor: pointer; transition: opacity 0.15s ease; }
.status-pill:hover { opacity: 0.75; }
.status-pill.status-draft { background: var(--color-warning-bg);
                            color: var(--color-warning-text); }
.status-pill.status-private { background: #6b21a8; color: #f3e8ff; }
.status-pill.status-public { background: var(--color-success-bg);
                             color: var(--color-success-text); }
.status-pill.status-unlisted { background: #1e40af; color: #dbeafe; }
.status-pill-menu { position: relative; display: inline-block; }
.status-pill-menu > summary { list-style: none; cursor: pointer; }
.status-pill-menu > summary::-webkit-details-marker { display: none; }
.status-pill-menu .pill-menu {
  position: absolute; top: 100%; left: 0; z-index: 10;
  background: var(--color-surface, #1e293b);
  border: 1px solid var(--color-border, #334155);
  border-radius: 6px; padding: 0.25rem; margin-top: 0.25rem;
  display: flex; flex-direction: column; min-width: 100px;
}
.status-pill-menu .pill-menu button {
  background: none; border: none; color: inherit;
  text-align: left; padding: 0.4rem 0.75rem; cursor: pointer;
  border-radius: 4px; font-size: 0.85rem;
}
.status-pill-menu .pill-menu button:hover {
  background: var(--color-bg, #0f172a);
}
.actions-cell { display: flex; gap: 0.75rem; align-items: center; }
.actions-cell form { margin: 0; }
.flash-message { padding: 0.75rem 1rem; border-radius: 6px;
                 margin-bottom: 1rem; font-size: 0.9rem; }
.flash-message.success { background: var(--color-success-bg);
                         color: var(--color-success-text); }
.flash-message.error { background: var(--color-error-bg);
                       color: var(--color-error-text); }
tr.htmx-swapping { opacity: 0; transition: opacity 0.3s ease; }")

(defun render-notebook-state-dropdown (id status visibility)
  "Render the notebook status pill wrapped in a <details>/<summary>
dropdown with four HTMX buttons (Draft / Private / Unlisted / Public).

The outer <details> element gets id=state-dropdown-{ID} and the HTMX
buttons target it with hx-swap=\"outerHTML\" so a state change replaces
the entire dropdown markup (preserving the dropdown structure across
clicks). The inner <summary> keeps id=status-{ID} so any external code
referencing the pill by that id continues to work."
  (let* ((status-lower (string-downcase (or status "draft")))
         (visibility-lower (string-downcase (or visibility "private")))
         (state-class
          (cond ((equal status-lower "draft") "status-draft")
                ((equal visibility-lower "public") "status-public")
                ((equal visibility-lower "unlisted") "status-unlisted")
                (t "status-private")))
         (label
          (cond ((equal status-lower "draft") (tr :common.visibility.draft))
                ((equal visibility-lower "public") (tr :common.visibility.public))
                ((equal visibility-lower "unlisted") (tr :common.visibility.unlisted))
                (t (tr :common.visibility.private))))
         (dropdown-id (format nil "state-dropdown-~A" id))
         (dropdown-target (format nil "#state-dropdown-~A" id))
         (state-url (format nil "/dashboard/notebooks/~A/state" id)))
    (with-html-string
      (:details :class "status-pill-menu" :id dropdown-id
        (:summary :class (format nil "status-pill ~A" state-class)
          :id (format nil "status-~A" id)
          :data-status status-lower
          :data-visibility visibility-lower
          label)
        (:div :class "pill-menu"
          (:button :type "button" :hx-post state-url
            :hx-vals "{\"state\":\"draft\"}"
            :hx-target dropdown-target :hx-swap "outerHTML"
            :hx-include "#csrf-form"
            (tr :common.visibility.draft))
          (:button :type "button" :hx-post state-url
            :hx-vals "{\"state\":\"published-private\"}"
            :hx-target dropdown-target :hx-swap "outerHTML"
            :hx-include "#csrf-form"
            (tr :common.visibility.private))
          (:button :type "button" :hx-post state-url
            :hx-vals "{\"state\":\"published-unlisted\"}"
            :hx-target dropdown-target :hx-swap "outerHTML"
            :hx-include "#csrf-form"
            (tr :common.visibility.unlisted))
          (:button :type "button" :hx-post state-url
            :hx-vals "{\"state\":\"published-public\"}"
            :hx-target dropdown-target :hx-swap "outerHTML"
            :hx-include "#csrf-form"
            (tr :common.visibility.public)))))))

(defun render (&key user notebooks pagination message errors)
  "Render the admin notebook list page as an HTML string.

NOTEBOOKS is a list of plists with :id :title :slug :status
:published-at :created-at."
  (let ((user-timezone (getf user :timezone))
        (user-handle (getf user :handle))
        (styles (concatenate 'string (common-styles) *page-styles*)))
    (page-shell
     :title (tr :notebooks_dashboard.page_title)
     :styles styles
     :user user
     :body-content
     (with-html-string
       (:div :class "card"
        (:h1 (tr :notebooks_dashboard.heading))
        (:p :class "muted" (tr :notebooks_dashboard.subtitle))
        (:div :class "actions-bar"
         (:a :class "new-nb-btn" :href "/dashboard/notebooks/new"
          (tr :notebooks_dashboard.new_button)))
        (:div :id "flash-area"
         (when message (:div :class "flash-message success" message))
         (when errors
           (:div :class "flash-message error"
            (dolist (err errors) (:p err)))))
        (if notebooks
            (progn
             (:table
              (:thead
               (:tr (:th (tr :notebooks_dashboard.table.title))
                (:th (tr :notebooks_dashboard.table.status))
                (:th (tr :notebooks_dashboard.table.published))
                (:th (tr :notebooks_dashboard.table.created))
                (:th (tr :notebooks_dashboard.table.actions))))
              (:tbody :id "notebooks-body"
               (dolist (nb notebooks)
                 (let ((id (getf nb :id))
                       (slug (getf nb :slug))
                       (title (getf nb :title))
                       (status (getf nb :status))
                       (visibility (or (getf nb :visibility) "private"))
                       (published-at (getf nb :published-at))
                       (created-at (getf nb :created-at)))
                   (:tr :id (format nil "nb-row-~A" id)
                    (:td
                     (if (and slug user-handle (string= status "published"))
                         (:a :href (format nil "/@~A/~A" user-handle slug)
                          title)
                         title))
                    (:td
                     (:raw
                      (render-notebook-state-dropdown id status visibility)))
                    (:td
                     (if published-at
                         (or (format-timestamp published-at user-timezone)
                             "—")
                         "—"))
                    (:td
                     (or (format-timestamp created-at user-timezone) "—"))
                    (:td
                     (:div :class "actions-cell"
                      (:a :class "icon-action" :title (tr :common.actions.edit) :aria-label (tr :common.actions.edit)
                       :href (format nil "/dashboard/notebooks/~A/edit" id)
                       (:raw (icon "pen-to-square")))
                      (:button :class "icon-action danger" :title (tr :common.actions.delete)
                       :aria-label (tr :common.actions.delete) :hx-get
                       (format nil "/dashboard/notebooks/~A/confirm-delete"
                               id)
                       :hx-target "#modal-container" :hx-swap "innerHTML"
                       (:raw (icon "trash")))
                      (when (and (string= visibility "unlisted")
                                 slug user-handle)
                        (:button :type "button"
                         :class "icon-action copy-link-btn"
                         :title (tr :common.actions.copy_link) :aria-label (tr :common.actions.copy_link)
                         :data-share-url (format nil "/@~A/~A" user-handle slug)
                         :onclick "navigator.clipboard.writeText(location.origin+this.dataset.shareUrl)"
                         (:raw (icon "link")))))))))))
             (when pagination
               (let ((current-page (getf pagination :current-page))
                     (total-pages (getf pagination :total-pages))
                     (has-prev (getf pagination :has-prev))
                     (has-next (getf pagination :has-next))
                     (prev-url (getf pagination :prev-url))
                     (next-url (getf pagination :next-url)))
                 (:div :class "pagination"
                  (:span :class "pagination-info"
                   (format nil "Page ~A of ~A" current-page total-pages))
                  (:nav :class "pagination-nav"
                   (if has-prev
                       (:a :class "pagination-btn" :href prev-url
                        (:raw (icon "arrow-left"))
                        (tr :notebooks_dashboard.pagination.previous))
                       (:span :class "pagination-btn disabled"
                        (:raw (icon "arrow-left"))
                        (tr :notebooks_dashboard.pagination.previous)))
                   (if has-next
                       (:a :class "pagination-btn" :href next-url
                        (tr :notebooks_dashboard.pagination.next)
                        (:raw (icon "arrow-right")))
                       (:span :class "pagination-btn disabled"
                        (tr :notebooks_dashboard.pagination.next)
                        (:raw (icon "arrow-right")))))))))
            (:p :class "muted" (tr :notebooks_dashboard.empty_state))))
       (:div :id "modal-container")))))
