;;;; db/posts.lisp --- CRUD operations for the post table.
;;;;
;;;; Provides create, read, update, delete, listing, and counting for
;;;; blog posts.  Includes slug generation (slugify) and filtering by
;;;; status and author.

(defpackage #:recurya/db/posts
  (:use #:cl)
  (:import-from #:mito
                #:find-dao
                #:select-dao
                #:insert-dao
                #:save-dao
                #:delete-dao)
  (:import-from #:sxql
                #:where
                #:order-by
                #:limit)
  (:import-from #:recurya/db/core
                #:generate-uuid
                #:ensure-uuid)
  ;; Import post class and accessors from models
  (:import-from #:recurya/models/post
                #:post
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
                #:post-updated-at)
  (:export
   ;; Re-export the Mito class and accessors
   #:post
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
   #:post-updated-at
   ;; CRUD operations
   #:create-post!
   #:get-post-by-id
   #:get-post-by-slug
   #:update-post!
   #:delete-post!
   #:list-posts
   #:count-posts
   ;; Utilities
   #:slugify))

(in-package #:recurya/db/posts)

;;; ============================================================
;;; Utilities
;;; ============================================================

(defun slugify (title)
  "Convert TITLE to a URL-friendly slug.

Downcases, replaces non-alphanumeric characters with hyphens,
collapses consecutive hyphens, and trims leading/trailing hyphens.

Arguments:
  TITLE - A string to slugify.

Returns:
  A lowercase, hyphen-separated slug string."
  (let* ((lower (string-downcase title))
         ;; Replace non-alphanumeric (except hyphens) with hyphens
         (replaced (cl-ppcre:regex-replace-all "[^a-z0-9-]" lower "-"))
         ;; Collapse consecutive hyphens
         (collapsed (cl-ppcre:regex-replace-all "-+" replaced "-"))
         ;; Trim leading/trailing hyphens
         (trimmed (string-trim '(#\-) collapsed)))
    trimmed))

;;; ============================================================
;;; CRUD Operations
;;; ============================================================

(defun create-post! (&key title body
                          slug
                          excerpt
                          (status "draft")
                          published-at
                          author
                          post-id)
  "Create a new blog post and return the created instance.

Arguments:
  TITLE        - Post title (required)
  BODY         - Post body text (required)
  SLUG         - URL slug (optional, auto-generated from title if omitted)
  EXCERPT      - Short summary, max 500 chars (optional)
  STATUS       - \"draft\" or \"published\" (default: \"draft\")
  PUBLISHED-AT - Timestamp when published (optional)
  AUTHOR       - Users instance (optional)
  POST-ID      - Pre-generated UUID (optional)

Returns:
  The newly created POST instance."
  (let ((id (or post-id (generate-uuid)))
        (slug (or slug (slugify title))))
    (insert-dao (make-instance 'post
                               :id id
                               :title title
                               :slug slug
                               :body body
                               :excerpt excerpt
                               :status status
                               :published-at published-at
                               :author author))))

(defun get-post-by-id (post-id)
  "Fetch a post by UUID.

Returns:
  POST instance if found, NIL otherwise."
  (find-dao 'post :id (ensure-uuid post-id)))

(defun get-post-by-slug (slug)
  "Fetch a post by slug.

Returns:
  POST instance if found, NIL otherwise."
  (find-dao 'post :slug slug))

(defun update-post! (post-id &key title slug body excerpt status published-at author)
  "Update post attributes. Only provided fields are updated.

Returns:
  The updated POST instance, or NIL if not found."
  (let ((p (find-dao 'post :id (ensure-uuid post-id))))
    (when p
      (when title
        (setf (post-title p) title))
      (when slug
        (setf (post-slug p) slug))
      (when body
        (setf (post-body p) body))
      (when excerpt
        (setf (post-excerpt p) excerpt))
      (when status
        (setf (post-status p) status))
      (when published-at
        (setf (post-published-at p) published-at))
      (when author
        (setf (post-author p) author))
      (save-dao p))
    p))

(defun delete-post! (post-id)
  "Delete a post by UUID.

Returns:
  T if deleted, NIL if not found."
  (let ((p (find-dao 'post :id (ensure-uuid post-id))))
    (when p
      (delete-dao p)
      t)))

(defun list-posts (&key status author-id (limit 50) offset)
  "List posts, optionally filtered by status and/or author, newest first.

Arguments:
  STATUS    - Filter by status string (optional)
  AUTHOR-ID - Filter by author UUID (optional)
  LIMIT     - Maximum results (default: 50)
  OFFSET    - Number to skip (optional)

Returns:
  List of POST instances."
  ;; NOTE: Pagination is done in-memory with SUBSEQ after fetching all
  ;; matching rows via Mito's select-dao.  This is simple and sufficient
  ;; for a small blog, but for large datasets you'd want SQL-level
  ;; LIMIT/OFFSET (which requires raw SQL or SxQL workarounds with Mito).
  (let ((all (cond
               ((and status author-id)
                (select-dao 'post
                  (where (:and (:= :status status)
                               (:= :author_id author-id)))
                  (order-by (:desc :created-at))))
               (status
                (select-dao 'post
                  (where (:= :status status))
                  (order-by (:desc :created-at))))
               (author-id
                (select-dao 'post
                  (where (:= :author_id author-id))
                  (order-by (:desc :created-at))))
               (t
                (select-dao 'post
                  (order-by (:desc :created-at)))))))
    (cond
      ((and offset limit)
       (subseq all
               (min offset (length all))
               (min (+ offset limit) (length all))))
      (limit
       (subseq all 0 (min limit (length all))))
      (offset
       (subseq all (min offset (length all))))
      (t all))))

(defun count-posts (&key status author-id)
  "Count posts, optionally filtered by status and/or author.

Arguments:
  STATUS    - Filter by status string (optional)
  AUTHOR-ID - Filter by author UUID (optional)

Returns:
  Integer count."
  (let ((conditions nil)
        (binds nil))
    (when status
      (push "status = ?" conditions)
      (push status binds))
    (when author-id
      (push "author_id = ?" conditions)
      (push (princ-to-string author-id) binds))
    (let* ((where-clause (if conditions
                             (format nil " WHERE ~{~A~^ AND ~}" (nreverse conditions))
                             ""))
           (sql (concatenate 'string "SELECT COUNT(*) as count FROM post" where-clause))
           (binds (nreverse binds)))
      (let ((result (mito:retrieve-by-sql sql :binds binds)))
        (if result
            (getf (first result) :count)
            0)))))
