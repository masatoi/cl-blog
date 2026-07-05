;;;; tests/support/db.lisp --- Shared test utilities for database setup/teardown.
;;;;
;;;; Provides with-test-db, create-test-user, and create-test-post
;;;; helpers used by all database and integration test suites.

(defpackage #:recurya/tests/support/db
  (:use #:cl)
  (:import-from #:recurya/db/core
                #:execute!
                #:connect-to-database
                #:with-connection
                #:current-database)
  (:import-from #:recurya/db/users
                #:create-user!)
  (:import-from #:uuid
                #:make-v4-uuid)
  (:export
   ;; Database setup
   #:setup-test-db
   #:cleanup-all-test-data
   #:with-test-db
   #:test-database-name
   #:test-database-p
   #:ensure-test-database!
   ;; Entity creation
   #:create-test-user))

(in-package #:recurya/tests/support/db)

;;; ============================================================
;;; Database Setup
;;; ============================================================

(defun test-database-name ()
  "Name of the dedicated test database. Configurable via POSTGRES_TEST_DB;
defaults to the application database name (POSTGRES_DB, default \"recurya\")
suffixed with \"_test\"."
  (or (uiop:getenv "POSTGRES_TEST_DB")
      (concatenate 'string (or (uiop:getenv "POSTGRES_DB") "recurya") "_test")))

(defun test-database-p (name)
  "True iff NAME designates the dedicated test database. Used to guard
destructive cleanup so it can never run against the development database."
  (and (stringp name) (string= name (test-database-name))))

(defvar *test-db-initialized* nil
  "Set once the test database has been created and its schema applied in this
image, so setup work runs at most once per session.")

(defvar *test-connection* nil
  "Cached cl-dbi connection to the dedicated test database, reused across
tests. Separate from the application's top-level connection.")

(defun %apply-schema-file (conn)
  "Apply db/schema.sql to CONN, one statement at a time. The schema is plain
DDL (no PL/pgSQL bodies), so splitting on `;' is safe."
  (let ((sql (uiop:read-file-string
              (asdf:system-relative-pathname :recurya "db/schema.sql"))))
    (dolist (stmt (uiop:split-string sql :separator ";"))
      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) stmt)))
        (when (plusp (length trimmed))
          (dbi:do-sql conn trimmed))))))

(defun ensure-test-database! ()
  "Idempotently ensure the dedicated test database exists and has the schema
applied. Uses fresh maintenance connections only, so the running
application's top-level connection is never touched. Returns the test
database name."
  (let ((test-db (test-database-name)))
    ;; 1. Create the database if absent, via the `postgres' maintenance DB.
    ;;    CREATE DATABASE cannot run inside a transaction, so use DO-SQL on a
    ;;    fresh (autocommit) connection.
    (let ((admin (connect-to-database "postgres")))
      (unwind-protect
           (unless (dbi:fetch
                    (dbi:execute
                     (dbi:prepare
                      admin "SELECT 1 FROM pg_database WHERE datname = ?")
                     (list test-db)))
             (dbi:do-sql admin (format nil "CREATE DATABASE ~A" test-db)))
        (dbi:disconnect admin)))
    ;; 2. Apply the schema if the test DB has no `users' table yet.
    (let ((conn (connect-to-database test-db)))
      (unwind-protect
           (let ((regclass
                  (second (dbi:fetch
                           (dbi:execute
                            (dbi:prepare
                             conn "SELECT to_regclass('public.users')"))))))
             (when (or (null regclass) (eq regclass :null))
               (%apply-schema-file conn)))
        (dbi:disconnect conn)))
    test-db))

(defun ensure-test-db-ready ()
  "Ensure the test database exists (created + schema applied once) and that a
cached connection to it is open. Returns the cached test connection."
  (unless *test-db-initialized*
    (ensure-test-database!)
    (setf *test-db-initialized* t))
  (unless (and *test-connection*
               (handler-case (dbi:ping *test-connection*) (error () nil)))
    (setf *test-connection* (connect-to-database (test-database-name))))
  *test-connection*)

(defun setup-test-db ()
  "Ensure the dedicated test database is ready and return a connection to it.
Never touches the application's top-level connection. Idempotent and safe to
call multiple times."
  (ensure-test-db-ready))

(defun cleanup-all-test-data ()
  "Delete all rows created by tests. GUARDED: aborts with an error unless the
active connection is attached to the dedicated test database, so a stray test
run can never wipe the development database. Must be called within a
WITH-CONNECTION to the test database (as WITH-TEST-DB does)."
  (let ((db (current-database)))
    (unless (test-database-p db)
      (error "cleanup-all-test-data refused: active connection is on database ~
              ~S, not the test database ~S. Aborting to protect non-test data."
             db (test-database-name))))
  (execute! "DELETE FROM novel_state")
  (execute! "DELETE FROM course_notebook")
  (execute! "DELETE FROM course")
  (execute! "DELETE FROM notebook")
  (execute! "DELETE FROM learn_submission")
  (execute! "DELETE FROM learn_cell_code")
  (execute! "DELETE FROM learn_progress")
  (execute! "DELETE FROM users WHERE email LIKE '%@example.com'"))

(defmacro with-test-db (&body body)
  "Execute BODY against the dedicated test database with a clean slate.
Connects to (a cached connection to) the test database, dynamically binding
the connection specials for the extent of BODY so the running application's
`recurya' connection is never touched. Cleans test data before and after and
runs BODY in between.

Usage:
  (with-test-db
    (let ((user (create-test-user)))
      (ok (users-id user))))"
  `(let ((conn (setup-test-db)))
     (with-connection (conn)
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
