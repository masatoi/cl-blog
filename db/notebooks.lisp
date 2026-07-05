;;;; db/notebooks.lisp --- CRUD operations for user-authored notebooks.

(defpackage #:recurya/db/notebooks
  (:use #:cl)
  (:import-from #:mito
                #:find-dao
                #:select-dao
                #:insert-dao
                #:save-dao
                #:delete-dao)
  (:import-from #:sxql #:where #:order-by #:limit)
  (:import-from #:recurya/db/core #:generate-uuid #:ensure-uuid)
  (:import-from #:recurya/utils/common #:slugify)
  (:import-from #:recurya/db/jsonb #:lisp->jsonb #:jsonb->lisp)
  (:import-from #:recurya/models/users
                #:users
                #:users-id)
  (:import-from #:recurya/models/notebook
                #:notebook
                #:notebook-id
                #:notebook-slug
                #:notebook-title
                #:notebook-summary
                #:notebook-body-md
                #:notebook-cells
                #:notebook-status
                #:notebook-visibility
                #:notebook-published-at
                #:notebook-author
                #:notebook-author-id
                #:notebook-created-at
                #:notebook-updated-at)
  (:export #:notebook
           #:notebook-id
           #:notebook-slug
           #:notebook-title
           #:notebook-summary
           #:notebook-body-md
           #:notebook-cells
           #:notebook-status
           #:notebook-visibility
           #:notebook-published-at
           #:notebook-author
           #:notebook-author-id
           #:notebook-created-at
           #:notebook-updated-at
           #:create-notebook!
           #:get-notebook-by-id
           #:get-notebook-by-slug
           #:find-notebook-by-handle-and-slug
           #:list-public-notebooks-of
           #:update-notebook!
           #:delete-notebook!
           #:list-notebooks
           #:count-notebooks
           #:notebook-cells-parsed))

(in-package #:recurya/db/notebooks)

(defun create-notebook! (&key title body-md cells slug summary
                              (status "draft") visibility published-at
                              author notebook-id)
  "Create a new user-authored notebook and return the created instance.

Arguments:
  TITLE         - Notebook title (required)
  BODY-MD       - Body markdown text with cell fences (required)
  CELLS         - Parsed cell list serialized to JSONB (required; '() becomes \"[]\")
  SLUG          - URL slug (auto-generated from title if omitted)
  SUMMARY       - Short summary, max 500 chars (optional)
  STATUS        - \"draft\" or \"published\" (default: \"draft\")
  VISIBILITY    - \"private\" or \"public\" (default: \"private\")
  PUBLISHED-AT  - Timestamp when published (optional)
  AUTHOR        - Users instance (required, FK is NOT NULL)
  NOTEBOOK-ID   - Pre-generated UUID (optional)

Returns:
  The newly created NOTEBOOK instance."
  (let ((id (or notebook-id (generate-uuid)))
        (slug (or slug (slugify title)))
        (cells-json
         (if (null cells)
             "[]"
             (lisp->jsonb cells))))
    (insert-dao
     (make-instance 'notebook
                    :id id
                    :slug slug
                    :title title
                    :summary summary
                    :body-md body-md
                    :cells cells-json
                    :status status
                    :visibility (or visibility "private")
                    :published-at published-at
                    :author author))))

(defun get-notebook-by-id (id)
  "Fetch a notebook by UUID.

Returns:
  NOTEBOOK instance if found, NIL otherwise."
  (find-dao 'notebook :id (ensure-uuid id)))

(defun get-notebook-by-slug (slug)
  "Fetch a notebook by slug.

Returns:
  NOTEBOOK instance if found, NIL otherwise."
  (find-dao 'notebook :slug slug))

(defun find-notebook-by-handle-and-slug (handle slug)
  "Find a notebook by its author's HANDLE and the notebook SLUG.

Arguments:
  HANDLE - The author's URL handle (string).
  SLUG   - The notebook slug (string).

Returns:
  NOTEBOOK instance if both author and notebook exist, NIL otherwise."
  (when (and handle slug)
    (let ((author (find-dao 'users :handle handle)))
      (when author
        (find-dao 'notebook :author author :slug slug)))))

(defun update-notebook! (notebook-id &key title slug summary body-md cells
                                          status visibility published-at)
  "Update notebook attributes. Only provided fields are updated.

CELLS, when provided, is JSON-serialized via lisp->jsonb before write
(an empty list serializes to \"[]\").

Returns:
  The updated NOTEBOOK instance, or NIL if not found."
  (let ((nb (find-dao 'notebook :id (ensure-uuid notebook-id))))
    (when nb
      (when title (setf (notebook-title nb) title))
      (when slug (setf (notebook-slug nb) slug))
      (when summary (setf (notebook-summary nb) summary))
      (when body-md (setf (notebook-body-md nb) body-md))
      (when cells
        (setf (notebook-cells nb)
              (if (null cells)
                  "[]"
                  (lisp->jsonb cells))))
      (when status (setf (notebook-status nb) status))
      (when visibility (setf (notebook-visibility nb) visibility))
      (when published-at (setf (notebook-published-at nb) published-at))
      (save-dao nb))
    nb))

(defun delete-notebook! (notebook-id)
  "Delete a notebook by UUID.

Returns:
  T if deleted, NIL if not found."
  (let ((nb (find-dao 'notebook :id (ensure-uuid notebook-id))))
    (when nb (delete-dao nb) t)))

(defun list-notebooks (&key status author-id visibility (limit 50) offset)
  "List notebooks, optionally filtered by status, author, and/or visibility, newest first.

Arguments:
  STATUS     - Filter by status string (optional)
  AUTHOR-ID  - Filter by author UUID (optional)
  VISIBILITY - Filter by visibility string (optional)
  LIMIT      - Maximum results (default: 50)
  OFFSET     - Number to skip (optional)

Returns:
  List of NOTEBOOK instances."
  (let ((all
         (cond
           ((and status author-id visibility)
            (select-dao 'notebook
              (where (:and (:= :status status)
                           (:= :author_id author-id)
                           (:= :visibility visibility)))
              (order-by (:desc :created-at))))
           ((and status author-id)
            (select-dao 'notebook
              (where (:and (:= :status status) (:= :author_id author-id)))
              (order-by (:desc :created-at))))
           ((and status visibility)
            (select-dao 'notebook
              (where (:and (:= :status status) (:= :visibility visibility)))
              (order-by (:desc :created-at))))
           ((and author-id visibility)
            (select-dao 'notebook
              (where (:and (:= :author_id author-id)
                           (:= :visibility visibility)))
              (order-by (:desc :created-at))))
           (status
            (select-dao 'notebook (where (:= :status status))
              (order-by (:desc :created-at))))
           (author-id
            (select-dao 'notebook (where (:= :author_id author-id))
              (order-by (:desc :created-at))))
           (visibility
            (select-dao 'notebook (where (:= :visibility visibility))
              (order-by (:desc :created-at))))
           (t (select-dao 'notebook (order-by (:desc :created-at)))))))
    (cond
      ((and offset limit)
       (subseq all (min offset (length all))
               (min (+ offset limit) (length all))))
      (limit (subseq all 0 (min limit (length all))))
      (offset (subseq all (min offset (length all))))
      (t all))))

(defun count-notebooks (&key status author-id visibility)
  "Count notebooks, optionally filtered by status, author, and/or visibility.

Returns:
  Integer count."
  (let ((conditions nil) (binds nil))
    (when status (push "status = ?" conditions) (push status binds))
    (when author-id
      (push "author_id = ?" conditions)
      (push (princ-to-string author-id) binds))
    (when visibility
      (push "visibility = ?" conditions)
      (push visibility binds))
    (let* ((where-clause
             (if conditions
                 (format nil " WHERE ~{~A~^ AND ~}" (nreverse conditions))
                 ""))
           (sql
             (concatenate 'string "SELECT COUNT(*) as count FROM notebook"
                          where-clause))
           (binds (nreverse binds)))
      (let ((result (mito.db:retrieve-by-sql sql :binds binds)))
        (if result
            (getf (first result) :count)
            0)))))

(defun list-public-notebooks-of (user)
  "List published+public notebooks authored by USER, newest first.

Arguments:
  USER - A USERS DAO instance.

Returns:
  List of NOTEBOOK instances."
  (when user
    (select-dao 'notebook
      (where (:and (:= :author_id (users-id user))
                   (:= :status "published")
                   (:= :visibility "public")))
      (order-by (:desc :created-at)))))

(defun notebook-cells-parsed (nb)
  "Return the cells JSONB column of NB parsed back to Lisp data.
JSON arrays come back as vectors; JSON objects as hash-tables."
  (jsonb->lisp (notebook-cells nb)))
