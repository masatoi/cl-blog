;;;; web/ui/post-form.lisp --- Create/edit form for blog posts.

(defpackage #:cl-blog/web/ui/post-form
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:cl-blog/web/ui/layout
                #:header
                #:header-styles
                #:common-styles)
  (:export #:render))

(in-package #:cl-blog/web/ui/post-form)

(defparameter *form-page-styles*
  "/* Post form page styles */
.post-form {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.form-group label {
  font-weight: 600;
  font-size: 0.9rem;
}

.form-group input,
.form-group textarea,
.form-group select {
  width: 100%;
  box-sizing: border-box;
}

.form-group textarea {
  min-height: 200px;
  resize: vertical;
}

.form-group textarea.body-field {
  min-height: 400px;
}

.form-hint {
  color: var(--color-text-muted);
  font-size: 0.8rem;
}

.form-actions {
  display: flex;
  gap: 0.75rem;
  margin-top: 0.5rem;
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
}")

(defun render (&key user post message errors)
  "Render the post create/edit form as an HTML string.

POST is a plist with :id :title :slug :body :excerpt :status when editing.
When POST is NIL, renders a new post form."
  (let* ((editing-p (not (null post)))
         (post-id (getf post :id))
         (post-title (or (getf post :title) ""))
         (post-slug (or (getf post :slug) ""))
         (post-body (or (getf post :body) ""))
         (post-excerpt (or (getf post :excerpt) ""))
         (post-status (or (getf post :status) "draft"))
         (action-url (if editing-p
                         (format nil "/posts/~A" post-id)
                         "/posts"))
         (page-title (if editing-p "Edit Post" "New Post"))
         (all-styles
          (concatenate 'string (common-styles) (header-styles) *form-page-styles*)))
    (spinneret:with-html-string
      (:doctype)
      (:html
       (:head (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title (format nil "cl-blog - ~A" page-title))
        (:style (:raw all-styles)))
       (:body (:raw (header user))
        (:main
         (:div :class "card"
          (:h1 page-title)
          (when message
            (:div :class "flash-message success" message))
          (when errors
            (:div :class "flash-message error"
             (dolist (err errors) (:p err))))
          (:form :class "post-form" :method "post" :action action-url
           (:div :class "form-group"
            (:label :for "title" "Title")
            (:input :type "text" :id "title" :name "title"
             :value post-title :required t
             :placeholder "Enter post title"))
           (:div :class "form-group"
            (:label :for "slug" "Slug")
            (:input :type "text" :id "slug" :name "slug"
             :value post-slug
             :placeholder "auto-generated-from-title")
            (:span :class "form-hint" "Leave blank to auto-generate from title."))
           (:div :class "form-group"
            (:label :for "excerpt" "Excerpt")
            (:textarea :id "excerpt" :name "excerpt"
             :placeholder "Brief summary (max 500 characters)"
             :maxlength "500"
             post-excerpt))
           (:div :class "form-group"
            (:label :for "body" "Body")
            (:textarea :id "body" :name "body" :class "body-field"
             :required t
             :placeholder "Write your post content here..."
             post-body))
           (:div :class "form-group"
            (:label :for "status" "Status")
            (:select :id "status" :name "status"
             (:option :value "draft"
              :selected (when (equal post-status "draft") "selected")
              "Draft")
             (:option :value "published"
              :selected (when (equal post-status "published") "selected")
              "Published")))
           (:div :class "form-actions"
            (:button :type "submit" :class "btn-primary"
             (if editing-p "Update Post" "Create Post"))
            (:a :class "btn-secondary" :href "/posts"
             :style "text-decoration:none;text-align:center"
             "Cancel"))))))))))
