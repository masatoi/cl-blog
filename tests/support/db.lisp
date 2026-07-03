;;;; tests/support/db.lisp --- Shared test utilities for database setup/teardown.
;;;;
;;;; Provides with-test-db, create-test-user, and create-test-post
;;;; helpers used by all database and integration test suites.

(defpackage #:recurya/tests/support/db
  (:use #:cl)
  (:import-from #:recurya/db/core
                #:build-connection-spec
                #:with-database
                #:execute-query
                #:execute!)
  (:import-from #:recurya/db/users
                #:users-id
                #:create-user!)
  (:import-from #:uuid
                #:make-v4-uuid)
  (:export
   ;; Database setup
   #:test-db-name
   #:ensure-test-database!
   #:cleanup-all-test-data
   #:with-test-db
   ;; Entity creation
   #:create-test-user))

(in-package #:recurya/tests/support/db)

;;; ============================================================
;;; Database Setup
;;; ============================================================

(defun test-db-name ()
  "Name of the dedicated test database.

Read from POSTGRES_TEST_DB, defaulting to \"recurya_test\". This is
ALWAYS a database distinct from the application's POSTGRES_DB, so the
suite can never touch production data."
  (or (uiop:getenv "POSTGRES_TEST_DB") "recurya_test"))

(defvar *test-db-initialized* nil
  "T once the test database has been created and its schema applied.
Lets WITH-TEST-DB skip the idempotent bootstrap after the first use.")

(defun %schema-statements ()
  "Return the individual SQL statements in db/schema.sql.

The schema file is plain CREATE TABLE/INDEX statements (no functions,
triggers, or dollar-quoting), so splitting on ';' is safe. Blank
fragments are dropped."
  (let ((sql (uiop:read-file-string
              (asdf:system-relative-pathname :recurya "db/schema.sql"))))
    (remove-if (lambda (s)
                 (zerop (length (string-trim '(#\Space #\Tab #\Newline #\Return)
                                             s))))
               (uiop:split-string sql :separator ";"))))

(defun %create-test-database-if-absent ()
  "Create the test database if it does not exist yet.

Connects to the maintenance \"postgres\" database to issue CREATE
DATABASE — you cannot CREATE a database from a connection to it. Never
connects to (or touches) the production database."
  (let ((admin (apply #'dbi:connect
                      (build-connection-spec :database-name "postgres"))))
    (unwind-protect
         (let* ((stmt (dbi:prepare
                       admin "SELECT 1 FROM pg_database WHERE datname = $1"))
                (exists (dbi:fetch (dbi:execute stmt (list (test-db-name))))))
           (unless exists
             (dbi:do-sql admin
                         (format nil "CREATE DATABASE \"~A\"" (test-db-name)))))
      (dbi:disconnect admin))))

(defun %apply-test-schema-if-empty ()
  "Apply db/schema.sql to the test database if it has no tables yet."
  (let ((conn (apply #'dbi:connect
                     (build-connection-spec :database-name (test-db-name)))))
    (unwind-protect
         (let* ((stmt (dbi:prepare
                       conn
                       "SELECT 1 FROM information_schema.tables
                        WHERE table_schema = 'public' AND table_name = 'users'"))
                (has-tables (dbi:fetch (dbi:execute stmt nil))))
           (unless has-tables
             (dolist (statement (%schema-statements))
               (dbi:do-sql conn statement))))
      (dbi:disconnect conn))))

(defun ensure-test-database! ()
  "Idempotently create the dedicated test database and apply its schema.

Safe to call repeatedly; the actual bootstrap runs once per Lisp image
(guarded by *TEST-DB-INITIALIZED*). Runs outside any WITH-DATABASE scope,
opening its own short-lived connections, so it never depends on the
current *DATASOURCE*."
  (unless *test-db-initialized*
    (%create-test-database-if-absent)
    (%apply-test-schema-if-empty)
    (setf *test-db-initialized* t)))

(defun cleanup-all-test-data ()
  "Delete all rows from the mutable tables in the TEST database.

Guards every wipe with a CURRENT_DATABASE() check: if the current
connection is not the dedicated test database (TEST-DB-NAME), it signals
an error and deletes nothing. Combined with WITH-DATABASE's thread-local
binding, this makes it impossible to wipe the production database — the
mistake this module previously allowed by running unconditional deletes
against whatever database happened to be connected."
  (let ((current (getf (first (execute-query "SELECT current_database() AS db"))
                       :|db|)))
    (unless (and current (string= current (test-db-name)))
      (error "cleanup-all-test-data refused: connected to ~S, not the test ~
              database ~S. No rows were deleted."
             current (test-db-name))))
  (execute! "DELETE FROM novel_state")
  (execute! "DELETE FROM course_notebook")
  (execute! "DELETE FROM course")
  (execute! "DELETE FROM notebook")
  (execute! "DELETE FROM learn_submission")
  (execute! "DELETE FROM learn_cell_code")
  (execute! "DELETE FROM learn_progress")
  (execute! "DELETE FROM users"))

(defmacro with-test-db (&body body)
  "Execute BODY against the dedicated test database.

On first use it creates the test database and applies the schema
(ENSURE-TEST-DATABASE!). It then binds the connection thread-locally via
WITH-DATABASE — so a co-hosted web server keeps its own production
connection on other threads — wipes the test tables before and after
BODY, and returns BODY's value. Every wipe is guarded by
CLEANUP-ALL-TEST-DATA's CURRENT_DATABASE() check.

Usage:
  (with-test-db
    (let ((user (create-test-user)))
      (ok (users-id user))))"
  `(progn
     (ensure-test-database!)
     (with-database ((build-connection-spec :database-name (test-db-name)))
       (cleanup-all-test-data)
       (unwind-protect
            (progn ,@body)
         (cleanup-all-test-data)))))

;;; ============================================================
;;; Test Entity Creation
;;; ============================================================

(defun create-test-user (&key (email-prefix "test")
                              (display-name "Test User")
                              (handle (format nil "u-~A" (make-v4-uuid))))
  "Create a unique test user and return the user struct.

Arguments:
  EMAIL-PREFIX  - Prefix for the email address (default: \"test\")
  DISPLAY-NAME  - Display name for the user (default: \"Test User\")
  HANDLE        - Per-user URL handle (default: unique UUID-based)

Returns:
  The created user struct with a unique UUID-based email."
  (create-user! :email (format nil "~A-~A@example.com" email-prefix (make-v4-uuid))
                :display-name display-name
                :handle handle
                :password-hash "test-hash"
                :password-salt "test-salt"
                :role "user"))
