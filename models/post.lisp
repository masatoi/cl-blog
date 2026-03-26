;;;; models/post.lisp --- Mito ORM table definition for the post table.
;;;;
;;;; Defines the `post` table schema with UUID primary key, title, slug,
;;;; body, excerpt, status (draft/published), and a foreign-key reference
;;;; to the users table via the author column.

(defpackage #:recurya/models/post
  (:use #:cl
        #:mito)
  (:import-from #:recurya/models/users
                #:users
                #:users-id)
  (:export #:post
           #:post-id
           #:post-title
           #:post-slug
           #:post-body
           #:post-excerpt
           #:post-status
           #:post-published-at
           #:post-author
           #:post-author-id
           #:post-created-at
           #:post-updated-at))

(in-package #:recurya/models/post)

(deftable post ()
  ((id :col-type :uuid
       :initarg :id
       :accessor %post-id
       :primary-key t)
   (title :col-type (:varchar 255)
          :initarg :title
          :accessor post-title)
   (slug :col-type (:varchar 255)
         :initarg :slug
         :accessor post-slug)
   (body :col-type :text
         :initarg :body
         :accessor post-body)
   (excerpt :col-type (or (:varchar 500) :null)
            :initarg :excerpt
            :initform nil
            :accessor post-excerpt)
   (status :col-type (:varchar 32)
           :initarg :status
           :initform "draft"
           :accessor post-status)
   (published-at :col-type (or :timestamptz :null)
                 :initarg :published-at
                 :initform nil
                 :accessor post-published-at)
   (author :col-type (or users :null)
           :initarg :author
           :initform nil
           :accessor post-author))
  ;; Disable Mito's auto-generated integer PK; we use an explicit UUID column.
  (:auto-pk nil)
  (:unique-keys slug)
  (:keys (status :created_at))
  (:documentation "Blog post entity with UUID primary key, slug-based URLs, and draft/published workflow."))

(defun post-id (post)
  "Return the UUID primary key for POST."
  (%post-id post))

(defun post-author-id (post)
  "Return the author user UUID, or NIL."
  (let ((u (post-author post)))
    (when u (users-id u))))

(defun post-created-at (post)
  "Return the creation timestamp for POST."
  (mito:object-created-at post))

(defun post-updated-at (post)
  "Return the last-updated timestamp for POST."
  (mito:object-updated-at post))
