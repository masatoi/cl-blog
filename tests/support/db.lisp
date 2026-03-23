;;;; tests/support/db.lisp --- Shared test utilities for database setup/teardown.
;;;;
;;;; Provides with-test-db, create-test-user, and create-test-post
;;;; helpers used by all database and integration test suites.

(defpackage #:cl-blog/tests/support/db
  (:use #:cl)
  (:import-from #:cl-blog/db/core
                #:start!
                #:execute!
                #:datasource)
  (:import-from #:cl-blog/db/users
                #:users-id
                #:create-user!)
  (:import-from #:cl-blog/db/posts
                #:post-id
                #:create-post!)
  (:import-from #:uuid
                #:make-v4-uuid)
  (:export
   ;; Database setup
   #:setup-test-db
   #:cleanup-all-test-data
   #:with-test-db
   ;; Entity creation
   #:create-test-user
   ;; Blog post entity creation
   #:create-test-post))

(in-package #:cl-blog/tests/support/db)

;;; ============================================================
;;; Database Setup
;;; ============================================================

(defun setup-test-db ()
  "Ensure the database is started (but don't restart if already running).
This is idempotent and safe to call multiple times."
  (unless (datasource)
    (start!)))

(defun cleanup-all-test-data ()
  "Remove all test data to ensure clean state.
Only deletes data matching test patterns to avoid affecting production data."
  (ignore-errors
    (execute! "DELETE FROM post")
    (execute! "DELETE FROM users WHERE email LIKE '%@example.com'")))

(defmacro with-test-db (&body body)
  "Execute BODY with a fresh database state.
Sets up the database connection, cleans existing test data,
executes BODY, then cleans up again.

Usage:
  (with-test-db
    (let ((user (create-test-user)))
      (ok (users-id user))))"
  `(progn
     (setup-test-db)
     (cleanup-all-test-data)
     (unwind-protect
          (progn ,@body)
       (cleanup-all-test-data))))

;;; ============================================================
;;; Test Entity Creation
;;; ============================================================

(defun create-test-user (&key (email-prefix "test") (display-name "Test User"))
  "Create a unique test user and return the user struct.

Arguments:
  EMAIL-PREFIX  - Prefix for the email address (default: \"test\")
  DISPLAY-NAME  - Display name for the user (default: \"Test User\")

Returns:
  The created user struct with a unique UUID-based email."
  (create-user! :email (format nil "~A-~A@example.com" email-prefix (make-v4-uuid))
                :display-name display-name
                :password-hash "test-hash"
                :password-salt "test-salt"
                :role "user"))

(defun create-test-post (&key (title-prefix "Test Post") (body "Test body content.")
                              (status "draft") (excerpt nil))
  "Create a unique test blog post and return the post instance.

Arguments:
  TITLE-PREFIX - Prefix for the title (default: \"Test Post\")
  BODY         - Post body text (default: \"Test body content.\")
  STATUS       - Status string (default: \"draft\")
  EXCERPT      - Short summary (optional)

Returns:
  The created post instance with a unique slug."
  (let ((unique-title (format nil "~A ~A" title-prefix (make-v4-uuid))))
    (create-post! :title unique-title
                  :body body
                  :status status
                  :excerpt excerpt)))
