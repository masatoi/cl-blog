(defpackage #:cl-blog/db/core
  (:use #:cl)
  (:import-from #:mito
                #:connect-toplevel
                #:disconnect-toplevel
                #:*connection*)
  (:import-from #:dbi
                #:execute
                #:fetch-all
                #:fetch)
  (:import-from #:log4cl)
  (:import-from #:cl-blog/utils/common
                #:generate-uuid
                #:parse-json
                #:json->string)
  (:export
   ;; Connection management
   #:start!
   #:stop!
   #:datasource
   #:with-transaction
   ;; Constants
   #:*active-job-statuses*
   ;; Value conversion utilities
   #:nil->null
   #:null->nil
   #:ensure-uuid
   #:generate-uuid
   #:keyword->db-string
   #:clj->json-str
   #:json-str->clj
   #:maybe-instant
   #:format-timestamp-for-db
   ;; Query execution
   #:execute-query
   #:execute-one
   #:execute!))

(in-package #:cl-blog/db/core)

;;; ============================================================
;;; Configuration
;;; ============================================================

(defvar *datasource* nil
  "Current active database connection handle.
This is set by START! and cleared by STOP!. Use DATASOURCE function
to access the connection, which will auto-initialize if needed.")

(defvar *db-config* nil
  "Current database configuration as a property list.
Contains :database-name, :host, :port, :username, and :password.")

;; Disable Mito's auto-migration to prevent schema changes on system load.
;; Use Mito CLI for all schema modifications:
;;   .qlot/bin/mito generate-migrations ...
;;   .qlot/bin/mito migrate ...
(setf mito:*auto-migration-mode* nil)

;;; ============================================================
;;; Constants
;;; ============================================================

(defparameter *active-job-statuses* '("queued" "running")
  "Job statuses that indicate active processing.
Jobs in these states block feature modifications and indicate
that the dataset is currently being processed.")

(defun get-env (name &optional default)
  "Get environment variable with optional default value."
  (or (uiop:getenv name) default))

(defun build-connection-spec ()
  "Build Mito connection spec from environment variables."
  (let ((host (get-env "POSTGRES_HOST" "localhost"))
        (port (parse-integer (get-env "POSTGRES_PORT" "5432")))
        (db (get-env "POSTGRES_DB" "cl_blog"))
        (user (get-env "POSTGRES_USER" "postgres"))
        (password (get-env "POSTGRES_PASSWORD" "postgres")))
    (list :postgres
          :database-name db
          :host host
          :port port
          :username user
          :password password)))

;;; ============================================================
;;; Connection Management
;;; ============================================================

(declaim (ftype (function (&optional t) t) start!))
(defun start! (&optional jdbc-url)
  "Initialize database connection.

Arguments:
  JDBC-URL - Ignored (for Clojure compatibility). Uses environment variables.

Environment Variables:
  POSTGRES_HOST     - Database host (default: localhost)
  POSTGRES_PORT     - Database port (default: 5432)
  POSTGRES_DB       - Database name (default: cl_blog)
  POSTGRES_USER     - Username (default: postgres)
  POSTGRES_PASSWORD - Password (default: postgres)

Returns:
  The database connection object.

Side Effects:
  - Sets *DATASOURCE* and *DB-CONFIG*

Note:
  Migrations are handled via Mito CLI. Run `mito migrate` before
  starting the application if schema changes are pending."
  (declare (ignore jdbc-url))
  (let* ((spec (build-connection-spec))
         (conn-args (cdr spec)))  ; Skip :postgres driver type
    (log:info "Connecting to database: ~A@~A:~A/~A" (getf conn-args :username)
              (getf conn-args :host) (getf conn-args :port) (getf conn-args :database-name))
    (apply #'connect-toplevel spec)
    (setf *datasource* mito.connection:*connection*)
    (setf *db-config* spec)
    ;; Note: Migrations are now handled via Mito CLI, not at startup.
    ;; Run `mito migrate` before starting the application.
    (log:info "Database connection established")
    *datasource*))

(declaim (ftype (function () null) stop!))
(defun stop! ()
  "Close database connection and clear connection state.

Side Effects:
  - Disconnects from the database
  - Sets *DATASOURCE* and *DB-CONFIG* to NIL
  - Logs connection closure"
  (when *datasource*
    (disconnect-toplevel)
    (setf *datasource* nil)
    (setf *db-config* nil)
    (log:info "Database connection closed"))
  nil)

(declaim (ftype (function () t) datasource))
(defun datasource ()
  "Get current datasource, initializing if needed.

Returns:
  The active database connection. If no connection exists,
  automatically calls START! to establish one."
  (or *datasource* (start!)))

(defmacro with-transaction (&body body)
  "Execute BODY within a database transaction.

All database operations within BODY are wrapped in a transaction.
If BODY completes normally, the transaction is committed.
If an error is signaled, the transaction is rolled back.

Returns:
  The value(s) returned by the last form in BODY."
  `(dbi:with-transaction ((datasource))
     ,@body))

;;; ============================================================
;;; Value Conversion Utilities
;;; ============================================================

(declaim (ftype (function (t) t) nil->null))
(defun nil->null (value)
  "Convert NIL to :NULL for cl-dbi, pass through other values.

Arguments:
  VALUE - Any Lisp value.

Returns:
  :NULL if VALUE is NIL, otherwise VALUE unchanged.

Use this when writing values to the database to ensure proper
NULL handling by cl-dbi."
  (if (null value) :null value))

(declaim (ftype (function (t) t) null->nil))
(defun null->nil (value)
  "Convert :NULL from cl-dbi back to NIL.

Arguments:
  VALUE - A value read from the database.

Returns:
  NIL if VALUE is :NULL, otherwise VALUE unchanged.

Use this when reading values from the database to convert
cl-dbi's :NULL representation back to standard Lisp NIL."
  (if (eq value :null) nil value))

(declaim (ftype (function ((or keyword null)) (or string null)) keyword->db-string))
(defun keyword->db-string (kw)
  "Convert keyword to lowercase database string.

Arguments:
  KW - A keyword symbol, or NIL.

Returns:
  Lowercase string representation of the keyword's name,
  or NIL if KW is NIL.

Example:
  (keyword->db-string :PENDING) => \"pending\""
  (when kw
    ;; Pre-condition: if non-NIL, must be a keyword
    (check-type kw keyword)
    (string-downcase (symbol-name kw))))

(declaim (ftype (function (local-time:timestamp) string) format-timestamp-for-db))
(defun format-timestamp-for-db (timestamp)
  "Format a local-time timestamp for PostgreSQL storage.

Arguments:
  TIMESTAMP - A local-time:timestamp object.

Returns:
  String in format 'YYYY-MM-DD HH:MM:SS.UUUUUU' suitable for
  PostgreSQL TIMESTAMP columns."
  ;; Pre-condition: must be a local-time timestamp
  (check-type timestamp local-time:timestamp)
  (local-time:format-timestring
   nil timestamp
   :format '(:year "-" (:month 2) "-" (:day 2) " "
             (:hour 2) ":" (:min 2) ":" (:sec 2) "." (:usec 6))))

(declaim (ftype (function (t) string) ensure-uuid))
(defun ensure-uuid (value)
  "Convert value to UUID string format.

Arguments:
  VALUE - A string or other printable value.

Returns:
  Lowercase, trimmed UUID string.

PostgreSQL normalizes UUIDs to lowercase, so we do the same
to ensure consistent comparisons and storage."
  (string-downcase
   (typecase value
     (string (string-trim '(#\Space) value))
     (otherwise (format nil "~A" value)))))

(declaim (ftype (function (t) (or string null)) clj->json-str))
(defun clj->json-str (value)
  "Convert Lisp value to JSON string for database storage.

Arguments:
  VALUE - Any Lisp value that can be serialized to JSON.

Returns:
  JSON string representation, or NIL if VALUE is NIL.

Uses centralized json->string wrapper for consistency."
  (json->string value))

(declaim (ftype (function (t) t) json-str->clj))
(defun json-str->clj (value)
  "Parse JSON string from database to Lisp value.

Arguments:
  VALUE - A JSON string, or any other value.

Returns:
  Parsed Lisp value (hash-table for objects, vector for arrays),
  or NIL if parsing fails or VALUE is not a valid JSON string.

Uses centralized parse-json wrapper which ensures consistent
hash-table output for JSON objects."
  (parse-json value))

(declaim (ftype (function (t) t) maybe-instant))
(defun maybe-instant (value)
  "Convert database timestamp to local-time timestamp.

Arguments:
  VALUE - One of:
    - local-time:timestamp: returned as-is
    - string: parsed as ISO-8601 timestamp
    - integer: interpreted as CL universal time
    - other: returned as-is

Returns:
  A local-time:timestamp object, or the original VALUE if
  it cannot be converted."
  (typecase value
    (local-time:timestamp value)
    (string (local-time:parse-timestring value))
    (integer (local-time:universal-to-timestamp value))
    (otherwise value)))

;;; ============================================================
;;; Query Execution
;;; ============================================================

(declaim (ftype (function (string &rest t) list) execute-query))
(defun execute-query (sql &rest params)
  "Execute a SELECT query and return all matching rows.

Arguments:
  SQL    - SQL query string with $1, $2, etc. placeholders.
  PARAMS - Values to bind to the placeholders.

Returns:
  List of rows, each row being a property list with column names
  as keywords (lowercase with | delimiters).

Example:
  (execute-query \"SELECT id, name FROM users WHERE role = $1\" \"admin\")"
  ;; Pre-condition: SQL must be a non-empty string
  (check-type sql string)
  (assert (plusp (length sql)) (sql) "SQL query must not be empty")
  (let* ((conn (datasource))
         (stmt (dbi.driver:prepare conn sql))
         (result (dbi.driver:execute stmt params)))
    (dbi.driver:fetch-all result)))

(declaim (ftype (function (string &rest t) (or list null)) execute-one))
(defun execute-one (sql &rest params)
  "Execute a query and return only the first matching row.

Arguments:
  SQL    - SQL query string with $1, $2, etc. placeholders.
  PARAMS - Values to bind to the placeholders.

Returns:
  First row as a property list, or NIL if no rows match.

Example:
  (execute-one \"SELECT * FROM users WHERE id = $1\" user-id)"
  ;; Pre-condition: SQL must be a non-empty string
  (check-type sql string)
  (assert (plusp (length sql)) (sql) "SQL query must not be empty")
  (let* ((conn (datasource))
         (stmt (dbi.driver:prepare conn sql))
         (result (dbi.driver:execute stmt params)))
    (dbi.driver:fetch result)))

(declaim (ftype (function (string &rest t) t) execute!))
(defun execute! (sql &rest params)
  "Execute a non-SELECT statement (INSERT, UPDATE, DELETE).

Arguments:
  SQL    - SQL statement with $1, $2, etc. placeholders.
  PARAMS - Values to bind to the placeholders.

Returns:
  Implementation-defined result from the database driver.

Example:
  (execute! \"UPDATE users SET name = $1 WHERE id = $2\" new-name user-id)"
  ;; Pre-condition: SQL must be a non-empty string
  (check-type sql string)
  (assert (plusp (length sql)) (sql) "SQL statement must not be empty")
  (let* ((conn (datasource))
         (stmt (dbi.driver:prepare conn sql)))
    (dbi.driver:execute stmt params)))
