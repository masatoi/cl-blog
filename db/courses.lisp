;;;; db/courses.lisp --- CRUD operations for courses.

(defpackage #:recurya/db/courses
  (:use #:cl)
  (:import-from #:mito
                #:find-dao
                #:select-dao
                #:insert-dao
                #:save-dao
                #:delete-dao)
  (:import-from #:sxql #:where #:order-by #:limit)
  (:import-from #:recurya/db/core #:generate-uuid #:ensure-uuid #:uuid-string-p)
  (:import-from #:recurya/utils/common #:slugify)
  (:import-from #:recurya/models/users
                #:users
                #:users-id)
  (:import-from #:recurya/models/course
                #:course
                #:course-id
                #:course-slug
                #:course-title
                #:course-summary
                #:course-status
                #:course-visibility
                #:course-published-at
                #:course-author
                #:course-author-id
                #:course-created-at
                #:course-updated-at)
  (:export #:course
           #:course-id
           #:course-slug
           #:course-title
           #:course-summary
           #:course-status
           #:course-visibility
           #:course-published-at
           #:course-author
           #:course-author-id
           #:course-created-at
           #:course-updated-at
           #:create-course!
           #:get-course-by-id
           #:get-course-by-slug
           #:find-course-by-handle-and-slug
           #:list-public-courses-of
           #:update-course!
           #:delete-course!
           #:list-courses
           #:count-courses))

(in-package #:recurya/db/courses)

(defun create-course! (&key title summary slug status visibility published-at
                            author course-id)
  "Create a new course and return the created instance.

Arguments:
  TITLE         - Course title (required)
  SUMMARY       - Short summary, max 500 chars (optional)
  SLUG          - URL slug (auto-generated from title if omitted)
  STATUS        - \"draft\" or \"published\" (default: \"draft\")
  VISIBILITY    - \"private\" or \"public\" (default: \"private\")
  PUBLISHED-AT  - Timestamp when published (optional)
  AUTHOR        - Users instance (required, FK is NOT NULL)
  COURSE-ID     - Pre-generated UUID (optional)

Returns:
  The newly created COURSE instance."
  (let ((id (or course-id (generate-uuid)))
        (slug (or slug (slugify title))))
    (insert-dao
     (make-instance 'course
                    :id id
                    :slug slug
                    :title title
                    :summary summary
                    :status (or status "draft")
                    :visibility (or visibility "private")
                    :published-at published-at
                    :author author))))

(defun get-course-by-id (id)
  "Fetch a course by UUID.

Returns:
  COURSE instance if found, NIL otherwise."
  (let ((uuid (and id (ensure-uuid id))))
    (when (uuid-string-p uuid)
      (find-dao 'course :id uuid))))

(defun get-course-by-slug (slug)
  "Fetch a course by slug.

Returns:
  COURSE instance if found, NIL otherwise."
  (find-dao 'course :slug slug))

(defun find-course-by-handle-and-slug (handle slug)
  "Find a course by its author's HANDLE and the course SLUG.

Arguments:
  HANDLE - The author's URL handle (string).
  SLUG   - The course slug (string).

Returns:
  COURSE instance if both author and course exist, NIL otherwise."
  (when (and handle slug)
    (let ((author (find-dao 'users :handle handle)))
      (when author
        (find-dao 'course :author author :slug slug)))))

(defun update-course! (course-id &key title slug summary status visibility
                                      published-at)
  "Update course attributes. Only provided fields are updated.

SLUG is updated only when non-nil and non-empty (mirroring update-notebook!).

Returns:
  The updated COURSE instance, or NIL if not found."
  (let ((c (find-dao 'course :id (ensure-uuid course-id))))
    (when c
      (when title (setf (course-title c) title))
      (when (and slug (not (string= "" slug))) (setf (course-slug c) slug))
      (when summary (setf (course-summary c) summary))
      (when status (setf (course-status c) status))
      (when visibility (setf (course-visibility c) visibility))
      (when published-at (setf (course-published-at c) published-at))
      (save-dao c))
    c))

(defun delete-course! (course-id)
  "Delete a course by UUID.

Returns:
  T if deleted, NIL if not found."
  (let ((c (find-dao 'course :id (ensure-uuid course-id))))
    (when c (delete-dao c) t)))

(defun list-courses (&key status author-id visibility (limit 50) offset)
  "List courses, optionally filtered by status, author, and/or visibility, newest first.

Arguments:
  STATUS     - Filter by status string (optional)
  AUTHOR-ID  - Filter by author UUID (optional)
  VISIBILITY - Filter by visibility string (optional)
  LIMIT      - Maximum results (default: 50)
  OFFSET     - Number to skip (optional)

Returns:
  List of COURSE instances."
  (let ((all
         (cond
           ((and status author-id visibility)
            (select-dao 'course
              (where (:and (:= :status status)
                           (:= :author_id author-id)
                           (:= :visibility visibility)))
              (order-by (:desc :created-at))))
           ((and status author-id)
            (select-dao 'course
              (where (:and (:= :status status) (:= :author_id author-id)))
              (order-by (:desc :created-at))))
           ((and status visibility)
            (select-dao 'course
              (where (:and (:= :status status) (:= :visibility visibility)))
              (order-by (:desc :created-at))))
           ((and author-id visibility)
            (select-dao 'course
              (where (:and (:= :author_id author-id)
                           (:= :visibility visibility)))
              (order-by (:desc :created-at))))
           (status
            (select-dao 'course (where (:= :status status))
              (order-by (:desc :created-at))))
           (author-id
            (select-dao 'course (where (:= :author_id author-id))
              (order-by (:desc :created-at))))
           (visibility
            (select-dao 'course (where (:= :visibility visibility))
              (order-by (:desc :created-at))))
           (t (select-dao 'course (order-by (:desc :created-at)))))))
    (cond
      ((and offset limit)
       (subseq all (min offset (length all))
               (min (+ offset limit) (length all))))
      (limit (subseq all 0 (min limit (length all))))
      (offset (subseq all (min offset (length all))))
      (t all))))

(defun count-courses (&key status author-id visibility)
  "Count courses, optionally filtered by status, author, and/or visibility.

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
             (concatenate 'string "SELECT COUNT(*) as count FROM course"
                          where-clause))
           (binds (nreverse binds)))
      (let ((result (mito.db:retrieve-by-sql sql :binds binds)))
        (if result
            (getf (first result) :count)
            0)))))

(defun list-public-courses-of (user)
  "List published+public courses authored by USER, newest first.

Arguments:
  USER - A USERS DAO instance.

Returns:
  List of COURSE instances."
  (when user
    (select-dao 'course
      (where (:and (:= :author_id (users-id user))
                   (:= :status "published")
                   (:= :visibility "public")))
      (order-by (:desc :created-at)))))
