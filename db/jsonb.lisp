;;;; db/jsonb.lisp --- PostgreSQL JSONB column helpers.
;;;;
;;;; Utilities for reading/writing JSONB columns: serialization
;;;; (lisp->jsonb, jsonb->lisp), accessor functions (json-get, etc.),
;;;; and SQL result key normalization for mixed-case column names.

(defpackage #:cl-blog/db/jsonb
  (:use #:cl)
  (:import-from #:cl-blog/utils/common
                #:parse-json
                #:json->string)
  (:export
   ;; SQL result key normalization
   #:normalize-sql-key
   #:sql-getf
   #:sql-result-value

   ;; JSONB column helpers
   #:jsonb->lisp
   #:lisp->jsonb

   ;; Type-safe JSON accessors
   #:json-get
   #:json-get-string
   #:json-get-number
   #:json-get-list
   #:json-get-bool

   ;; Iteration helpers
   #:json-keys
   #:json-values
   #:map-json))

(in-package #:cl-blog/db/jsonb)

;;; ============================================================
;;; SQL Result Key Normalization
;;; ============================================================
;;;
;;; PostgreSQL/cl-dbi returns column names as keywords. The exact format
;;; depends on the driver and quoting:
;;; - Standard columns: :COLUMN_NAME (uppercase)
;;; - Aliased with AS: :column_name or :|column_name| (case varies)
;;; - SXQL generates: (:as (:count :*) :job_count) -> varies by driver
;;;
;;; This module normalizes access to handle all variants.

(declaim (ftype (function (t) keyword) normalize-sql-key))
(defun normalize-sql-key (key)
  "Normalize a SQL result key to a consistent keyword format.

Converts various key formats to uppercase keywords with hyphens:
  :|job_count| -> :JOB-COUNT
  :job_count   -> :JOB-COUNT
  \"job_count\" -> :JOB-COUNT
  :JOB-COUNT   -> :JOB-COUNT

Arguments:
  KEY - Keyword, symbol, or string representing a column name.

Returns:
  Normalized keyword in uppercase with underscores replaced by hyphens."
  (let* ((name (etypecase key
                 (keyword (symbol-name key))
                 (symbol (symbol-name key))
                 (string key)))
         ;; Remove pipe quotes if present (from :|name| format)
         (clean (string-trim '(#\|) name))
         ;; Replace underscores with hyphens, uppercase
         (normalized (substitute #\- #\_ (string-upcase clean))))
    (intern normalized :keyword)))

(declaim (ftype (function (list t &optional t) t) sql-getf))
(defun sql-getf (plist key &optional default)
  "Get value from SQL result plist with key normalization.

Handles the inconsistency between PostgreSQL drivers returning
different key formats (:|job_count| vs :JOB-COUNT vs :job_count).

Arguments:
  PLIST   - Property list from SQL query result
  KEY     - Key to look up (will be normalized)
  DEFAULT - Value to return if key not found (default: NIL)

Returns:
  The value associated with KEY, or DEFAULT if not found.

Example:
  (sql-getf '(:|job_count| 5) :job-count) => 5
  (sql-getf '(:JOB-COUNT 5) :job_count)   => 5"
  ;; Pre-condition: plist must have even length (valid plist structure)
  (assert (evenp (length plist)) (plist)
          "PLIST must have even length, got ~D elements" (length plist))
  (let ((normalized-key (normalize-sql-key key)))
    ;; Try the normalized key first
    (loop for (k v) on plist by #'cddr
          when (eq (normalize-sql-key k) normalized-key)
            do (return-from sql-getf v))
    default))

(declaim (ftype (function (t t &optional t) t) sql-result-value))
(defun sql-result-value (row key &optional default)
  "Extract a single value from a SQL result row.

Convenience wrapper around sql-getf that also handles NIL rows.

Arguments:
  ROW     - A plist from SQL query result, or NIL
  KEY     - Key to look up
  DEFAULT - Value to return if not found

Returns:
  The value, or DEFAULT if ROW is NIL or KEY not found."
  (if row
      (sql-getf row key default)
      default))

;;; ============================================================
;;; JSONB Column Helpers
;;; ============================================================
;;;
;;; PostgreSQL JSONB columns are returned as strings by cl-postgres.
;;; Mito doesn't auto-serialize/deserialize these, so we need helpers.

(declaim (ftype (function (t) t) jsonb->lisp))
(defun jsonb->lisp (value)
  "Parse a JSONB column value from the database to Lisp data.

Handles:
  - JSON strings -> parsed Lisp (hash-table for objects, vector for arrays)
  - Already-parsed values (hash-table, vector) -> returned as-is
  - NIL/empty -> NIL

Arguments:
  VALUE - String from JSONB column, or already-parsed value.

Returns:
  Hash-table for JSON objects, vector for arrays, or appropriate Lisp type.
  NIL if VALUE is NIL, empty, or unparseable."
  (cond
    ;; Already parsed - pass through
    ((hash-table-p value) value)
    ;; String - parse it (must check before vectorp since strings are vectors)
    ((stringp value)
     (if (plusp (length value))
         (handler-case
             (parse-json value)
           (error () nil))
         nil))  ; Empty string -> NIL
    ;; Vector (JSON array already parsed) - pass through
    ((vectorp value) value)
    ;; NIL or other
    (t nil)))

(declaim (ftype (function (t) (or string null)) lisp->jsonb))
(defun lisp->jsonb (value)
  "Serialize Lisp data to JSON string for JSONB column storage.

Arguments:
  VALUE - Lisp data to serialize (hash-table, list, vector, etc.)

Returns:
  JSON string suitable for JSONB column, or NIL if VALUE is NIL."
  (when value
    (json->string value)))

;;; ============================================================
;;; Type-Safe JSON Accessors
;;; ============================================================
;;;
;;; jzon v1.1.4 returns:
;;; - Hash-tables for JSON objects (with string keys)
;;; - Vectors for JSON arrays
;;; - Numbers, strings, T/NIL for primitives
;;;
;;; These accessors provide consistent, type-safe access.

(declaim (ftype (function (t t &optional t) t) json-get))
(defun json-get (json-value key &optional default)
  "Get a value from a JSON object (hash-table) by key.

Handles both string and keyword keys for convenience.
Also handles the case where json-value is a raw JSON string.

Arguments:
  JSON-VALUE - Hash-table, JSON string, or NIL
  KEY        - String or keyword key to look up
  DEFAULT    - Value to return if not found

Returns:
  The value at KEY, or DEFAULT if not found."
  (let ((obj (if (stringp json-value)
                 (jsonb->lisp json-value)
                 json-value)))
    (when (hash-table-p obj)
      (let ((str-key (etypecase key
                       (string key)
                       (keyword (string-downcase (symbol-name key)))
                       (symbol (string-downcase (symbol-name key))))))
        (multiple-value-bind (value found-p)
            (gethash str-key obj)
          (if found-p value default))))))

(declaim (ftype (function (t t &optional string) (or string null)) json-get-string))
(defun json-get-string (json-value key &optional default)
  "Get a string value from a JSON object.

Arguments:
  JSON-VALUE - Hash-table or JSON string
  KEY        - Key to look up
  DEFAULT    - Default string if not found or not a string

Returns:
  String value, or DEFAULT."
  (let ((val (json-get json-value key)))
    (if (stringp val) val default)))

(declaim (ftype (function (t t &optional number) (or number null)) json-get-number))
(defun json-get-number (json-value key &optional default)
  "Get a number value from a JSON object.

Arguments:
  JSON-VALUE - Hash-table or JSON string
  KEY        - Key to look up
  DEFAULT    - Default number if not found or not a number

Returns:
  Number value, or DEFAULT."
  (let ((val (json-get json-value key)))
    (if (numberp val) val default)))

(declaim (ftype (function (t t &optional list) list) json-get-list))
(defun json-get-list (json-value key &optional default)
  "Get an array value from JSON as a list.

jzon returns arrays as vectors; this converts to list for easier
iteration with standard Lisp functions.

Arguments:
  JSON-VALUE - Hash-table or JSON string
  KEY        - Key to look up
  DEFAULT    - Default list if not found or not an array

Returns:
  List of values, or DEFAULT."
  (let ((val (json-get json-value key)))
    (cond
      ((vectorp val) (coerce val 'list))
      ((listp val) val)
      (t default))))

(declaim (ftype (function (t t &optional t) t) json-get-bool))
(defun json-get-bool (json-value key &optional default)
  "Get a boolean value from a JSON object.

JSON true -> T, JSON false/null -> NIL.

Arguments:
  JSON-VALUE - Hash-table or JSON string
  KEY        - Key to look up
  DEFAULT    - Default if key not found

Returns:
  T, NIL, or DEFAULT."
  (multiple-value-bind (val found-p)
      (let ((obj (if (stringp json-value)
                     (jsonb->lisp json-value)
                     json-value)))
        (when (hash-table-p obj)
          (let ((str-key (etypecase key
                           (string key)
                           (keyword (string-downcase (symbol-name key)))
                           (symbol (string-downcase (symbol-name key))))))
            (gethash str-key obj))))
    (if found-p
        (if val t nil)
        default)))

;;; ============================================================
;;; Iteration Helpers
;;; ============================================================

(declaim (ftype (function (t) list) json-keys))
(defun json-keys (json-value)
  "Get all keys from a JSON object as a list of strings.

Arguments:
  JSON-VALUE - Hash-table or JSON string

Returns:
  List of string keys, or NIL if not an object."
  (let ((obj (if (stringp json-value)
                 (jsonb->lisp json-value)
                 json-value)))
    (when (hash-table-p obj)
      (loop for key being the hash-keys of obj
            collect key))))

(declaim (ftype (function (t) list) json-values))
(defun json-values (json-value)
  "Get all values from a JSON object as a list.

Arguments:
  JSON-VALUE - Hash-table or JSON string

Returns:
  List of values, or NIL if not an object."
  (let ((obj (if (stringp json-value)
                 (jsonb->lisp json-value)
                 json-value)))
    (when (hash-table-p obj)
      (loop for val being the hash-values of obj
            collect val))))

(declaim (ftype (function (function t) list) map-json))
(defun map-json (function json-value)
  "Map a function over JSON object key-value pairs.

Arguments:
  FUNCTION   - Function of two arguments (key, value)
  JSON-VALUE - Hash-table or JSON string

Returns:
  List of results from calling FUNCTION on each key-value pair."
  ;; Pre-condition: first argument must be callable
  (check-type function function)
  (let ((obj (if (stringp json-value)
                 (jsonb->lisp json-value)
                 json-value)))
    (when (hash-table-p obj)
      (loop for key being the hash-keys of obj
            for val being the hash-values of obj
            collect (funcall function key val)))))
