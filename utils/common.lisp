(defpackage #:cl-blog/utils/common
  (:use #:cl)
  (:import-from #:uuid)
  (:import-from #:alexandria
                #:when-let)
  (:import-from #:com.inuoe.jzon
                #:parse
                #:stringify)
  (:export
   ;; UUID utilities
   #:generate-uuid
   ;; String utilities
   #:trim-whitespace
   #:blank-string-p
   #:normalize-string
   ;; JSON utilities
   #:parse-json
   #:json->string))

(in-package #:cl-blog/utils/common)

;;; ============================================================
;;; UUID Utilities
;;; ============================================================

(declaim (ftype (function () string) generate-uuid))
(defun generate-uuid ()
  "Generate a new UUID v4 string.

Returns a lowercase hyphenated UUID string in the format
xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx where x is any hexadecimal
digit and y is one of 8, 9, A, or B.

PostgreSQL normalizes UUIDs to lowercase, so we generate them
in lowercase to ensure consistent comparisons."
  (let ((uuid (string-downcase (format nil "~A" (uuid:make-v4-uuid)))))
    ;; Post-condition: verify UUID format
    (assert (and (= 36 (length uuid))
                 (char= #\- (char uuid 8))
                 (char= #\- (char uuid 13))
                 (char= #\- (char uuid 18))
                 (char= #\- (char uuid 23)))
            (uuid)
            "Generated UUID has invalid format: ~A" uuid)
    uuid))

;;; ============================================================
;;; String Utilities
;;; ============================================================

(defparameter *whitespace-chars*
  '(#\Space #\Tab #\Newline #\Return #\Page)
  "Standard whitespace characters used for trimming operations.
Includes space, tab, newline, carriage return, and page (form feed).")

(declaim (ftype (function (t) (or string null)) trim-whitespace))
(defun trim-whitespace (string)
  "Trim leading and trailing whitespace from STRING.

Arguments:
  STRING - Any value; only strings are processed.

Returns:
  The trimmed string if non-empty after trimming, NIL otherwise.
  Also returns NIL if STRING is not a string type."
  (when (and string (stringp string))
    (let ((trimmed (string-trim *whitespace-chars* string)))
      (when (plusp (length trimmed))
        trimmed))))

(declaim (ftype (function (t) boolean) blank-string-p))
(defun blank-string-p (string)
  "Test whether STRING is blank (nil, empty, or whitespace-only).

Arguments:
  STRING - Any value to test.

Returns:
  T if STRING is NIL, not a string, empty, or contains only whitespace.
  NIL otherwise."
  (or (null string)
      (not (stringp string))
      (zerop (length string))
      (every (lambda (c) (member c *whitespace-chars*)) string)))

(declaim (ftype (function (t) (or string null)) normalize-string))
(defun normalize-string (string)
  "Normalize STRING by trimming whitespace and converting to lowercase.

Arguments:
  STRING - Any value; only strings are processed.

Returns:
  The normalized (trimmed and lowercased) string if non-empty,
  NIL otherwise."
  (when-let ((trimmed (trim-whitespace string)))
    (string-downcase trimmed)))

;;; ============================================================
;;; JSON Utilities
;;; ============================================================

(declaim (ftype (function (t) t) parse-json))
(defun parse-json (value)
  "Parse JSON string to Lisp data structures.

Arguments:
  VALUE - A JSON string to parse. If VALUE is NIL, empty string,
          or not a string, returns NIL.

Returns:
  Parsed Lisp value where:
  - JSON objects become hash-tables (with string keys)
  - JSON arrays become vectors
  - JSON strings become strings
  - JSON numbers become numbers
  - JSON booleans become T/NIL
  - JSON null becomes NIL

Note:
  jzon v1.1.4 returns hash-tables for JSON objects by default.
  JSON arrays (including plist-like structures) become vectors.

  Use this function instead of calling jzon:parse directly."
  (when (and value (stringp value) (plusp (length value)))
    (handler-case (parse value) (error () nil))))

(declaim (ftype (function (t) (or string null)) json->string))
(defun json->string (value)
  "Convert Lisp value to JSON string.

Arguments:
  VALUE - Any Lisp value that can be serialized to JSON.

Returns:
  JSON string representation, or NIL if VALUE is NIL.

Uses com.inuoe.jzon for serialization."
  (when value
    (stringify value)))
