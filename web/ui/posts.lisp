;;;; web/ui/posts.lisp --- Admin posts list page with HTMX interactions.
;;;;
;;;; Renders the post management table with HTMX-powered status toggle
;;;; (click pill to swap draft/published) and delete confirmation modals
;;;; (hx-get loads modal fragment into #modal-container).

(defpackage #:recurya/web/ui/posts
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/layout
                #:header
                #:header-styles
                #:common-styles
                #:format-timestamp)
  (:export #:render))

(in-package #:recurya/web/ui/posts)

(defparameter *posts-styles*
  "/* Posts admin page styles */
.actions-bar {
  display: flex;
  justify-content: flex-end;
  margin-bottom: 1rem;
}

.new-post-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.5rem 1.2rem;
  border: none;
  border-radius: 6px;
  background: var(--color-primary);
  color: #fff;
  font-weight: 500;
  font-size: 0.85rem;
  cursor: pointer;
  text-decoration: none;
  transition: background 0.15s ease;
}

.new-post-btn:hover {
  background: var(--color-primary-hover);
  color: #fff;
  text-decoration: none;
}

.status-pill {
  cursor: pointer;
  transition: opacity 0.15s ease;
}

.status-pill:hover {
  opacity: 0.75;
}

.status-pill[data-status='draft'] {
  background: var(--color-warning-bg);
  color: var(--color-warning-text);
}

.status-pill[data-status='published'] {
  background: var(--color-success-bg);
  color: var(--color-success-text);
}

.actions-cell {
  display: flex;
  gap: 0.75rem;
  align-items: center;
}

.actions-cell form {
  margin: 0;
}

.flash-message {
  padding: 0.75rem 1rem;
  border-radius: 6px;
  margin-bottom: 1rem;
  font-size: 0.9rem;
}

.flash-message.success {
  background: var(--color-success-bg);
  color: var(--color-success-text);
}

.flash-message.error {
  background: var(--color-error-bg);
  color: var(--color-error-text);
}

tr.htmx-swapping {
  opacity: 0;
  transition: opacity 0.3s ease;
}")

(defun render (&key user posts pagination message errors)
  "Render the admin posts list page as an HTML string."
  (let ((posts (or posts 'nil))
        (user-timezone (getf user :timezone))
        (all-styles
         (concatenate 'string (common-styles) (header-styles) *posts-styles*)))
    (spinneret:with-html-string
      (:doctype)
      (:html
       (:head (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title "recurya - Blog Posts")
        (:script :src "https://unpkg.com/htmx.org@2.0.4"
         :integrity "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
         :crossorigin "anonymous")
        (:style (:raw all-styles)))
       (:body (:raw (header user))
        (:main
         (:div :class "card"
          (:h1 "Blog Posts")
          (:p :class "muted" "Manage your blog posts.")
          (:div :class "actions-bar"
           (:a :class "new-post-btn" :href "/posts/new" "+ New Post"))
          (:div :id "flash-area"
           (when message
             (:div :class "flash-message success" message))
           (when errors
             (:div :class "flash-message error"
              (dolist (err errors) (:p err)))))
          (if posts
              (progn
               (:table
                (:thead
                 (:tr (:th "Title") (:th "Status") (:th "Published") (:th "Created") (:th "Actions")))
                (:tbody :id "posts-body"
                 (dolist (post posts)
                   (let ((id (getf post :id))
                         (title (getf post :title))
                         (status (getf post :status))
                         (published-at (getf post :published-at))
                         (created-at (getf post :created-at)))
                     (:tr :id (format nil "post-row-~A" id)
                      (:td title)
                      (:td
                       (:span :class "status-pill"
                        :id (format nil "status-~A" id)
                        :data-status (string-downcase (or status "draft"))
                        :hx-post (format nil "/posts/~A/toggle-status" id)
                        :hx-target (format nil "#status-~A" id)
                        :hx-swap "outerHTML"
                        (string-capitalize (or status "draft"))))
                      (:td (if published-at
                               (or (format-timestamp published-at user-timezone) "—")
                               "—"))
                      (:td (or (format-timestamp created-at user-timezone) "—"))
                      (:td
                       (:div :class "actions-cell"
                        (:a :class "link" :href (format nil "/posts/~A/edit" id) "Edit")
                        (:button :class "button-danger btn-sm"
                         :hx-get (format nil "/posts/~A/confirm-delete" id)
                         :hx-target "#modal-container"
                         :hx-swap "innerHTML"
                         "Delete"))))))))
               ;; Pagination
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
                         (:a :class "pagination-btn" :href prev-url "← Previous")
                         (:span :class "pagination-btn disabled" "← Previous"))
                     (if has-next
                         (:a :class "pagination-btn" :href next-url "Next →")
                         (:span :class "pagination-btn disabled" "Next →")))))))
              (:p :class "muted" "No posts yet. Create your first post!"))))
        (:div :id "modal-container"))))))
