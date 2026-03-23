;;;; tests/db/core.lisp --- Tests for db/core value conversion and query utilities.

(defpackage #:cl-blog/tests/db/core
  (:use #:cl #:rove)
  (:import-from #:cl-blog/db/core
                #:nil->null
                #:null->nil
                #:keyword->db-string
                #:ensure-uuid
                #:clj->json-str
                #:json-str->clj
                #:maybe-instant
                #:format-timestamp-for-db))

(in-package #:cl-blog/tests/db/core)

;;; ============================================================
;;; nil->null / null->nil Tests
;;; ============================================================

(deftest test-nil->null-converts-nil
  (testing "converts NIL to :NULL"
    (ok (eq :null (nil->null nil)))))

(deftest test-nil->null-passes-through
  (testing "passes through non-NIL values"
    (ok (equal "hello" (nil->null "hello")))
    (ok (= 42 (nil->null 42)))
    (ok (eq :keyword (nil->null :keyword)))
    (ok (eq t (nil->null t)))))

(deftest test-null->nil-converts-null
  (testing "converts :NULL to NIL"
    (ok (null (null->nil :null)))))

(deftest test-null->nil-passes-through
  (testing "passes through non-:NULL values"
    (ok (equal "hello" (null->nil "hello")))
    (ok (= 42 (null->nil 42)))
    (ok (eq :keyword (null->nil :keyword)))
    (ok (null (null->nil nil)))))

(deftest test-nil-null-roundtrip
  (testing "nil->null and null->nil are inverses"
    (ok (null (null->nil (nil->null nil))))
    (ok (equal "test" (null->nil (nil->null "test"))))))

;;; ============================================================
;;; keyword->db-string Tests
;;; ============================================================

(deftest test-keyword->db-string-basic
  (testing "converts keyword to lowercase string"
    (ok (equal "pending" (keyword->db-string :pending)))
    (ok (equal "pending" (keyword->db-string :PENDING)))
    (ok (equal "running" (keyword->db-string :running)))))

(deftest test-keyword->db-string-hyphenated
  (testing "preserves hyphens in keyword names"
    (ok (equal "in-progress" (keyword->db-string :in-progress)))
    (ok (equal "job-count" (keyword->db-string :JOB-COUNT)))))

(deftest test-keyword->db-string-nil
  (testing "returns NIL for NIL input"
    (ok (null (keyword->db-string nil)))))

;;; ============================================================
;;; ensure-uuid Tests
;;; ============================================================

(deftest test-ensure-uuid-string
  (testing "normalizes UUID string"
    (ok (equal "abc-123" (ensure-uuid "ABC-123")))
    (ok (equal "abc-123" (ensure-uuid "  abc-123  ")))))

(deftest test-ensure-uuid-lowercase
  (testing "converts to lowercase"
    (ok (equal "550e8400-e29b-41d4-a716-446655440000"
               (ensure-uuid "550E8400-E29B-41D4-A716-446655440000")))))

(deftest test-ensure-uuid-other-types
  (testing "converts other types via format"
    ;; Symbols, numbers, etc. are converted via format
    (let ((result (ensure-uuid 123)))
      (ok (stringp result))
      (ok (equal "123" result)))))

;;; ============================================================
;;; clj->json-str / json-str->clj Tests
;;; ============================================================

(deftest test-clj->json-str-hash-table
  (testing "serializes hash-table to JSON string"
    (let* ((ht (make-hash-table :test 'equal))
           (_ (setf (gethash "key" ht) "value"))
           (result (clj->json-str ht)))
      (declare (ignore _))
      (ok (stringp result))
      (ok (search "key" result))
      (ok (search "value" result)))))

(deftest test-clj->json-str-nil
  (testing "returns NIL for NIL input"
    (ok (null (clj->json-str nil)))))

(deftest test-json-str->clj-object
  (testing "parses JSON object to hash-table"
    (let ((result (json-str->clj "{\"name\": \"test\"}")))
      (ok (hash-table-p result))
      (ok (equal "test" (gethash "name" result))))))

(deftest test-json-str->clj-array
  (testing "parses JSON array to vector"
    (let ((result (json-str->clj "[1, 2, 3]")))
      (ok (vectorp result))
      (ok (equalp #(1 2 3) result)))))

(deftest test-json-str->clj-invalid
  (testing "returns NIL for invalid JSON"
    (ok (null (json-str->clj "not json")))
    (ok (null (json-str->clj nil)))
    (ok (null (json-str->clj "")))))

(deftest test-clj-json-roundtrip
  (testing "clj->json-str and json-str->clj roundtrip"
    (let* ((ht (make-hash-table :test 'equal))
           (_ (progn
                (setf (gethash "name" ht) "Alice")
                (setf (gethash "count" ht) 42)))
           (json-str (clj->json-str ht))
           (parsed (json-str->clj json-str)))
      (declare (ignore _))
      (ok (equal "Alice" (gethash "name" parsed)))
      (ok (= 42 (gethash "count" parsed))))))

;;; ============================================================
;;; maybe-instant Tests
;;; ============================================================

(deftest test-maybe-instant-timestamp
  (testing "passes through timestamp unchanged"
    (let ((ts (local-time:now)))
      (ok (eq ts (maybe-instant ts))))))

(deftest test-maybe-instant-string
  (testing "parses ISO-8601 string"
    (let ((result (maybe-instant "2024-01-15T10:30:00Z")))
      (ok (typep result 'local-time:timestamp))
      (ok (= 2024 (local-time:timestamp-year result)))
      (ok (= 1 (local-time:timestamp-month result)))
      (ok (= 15 (local-time:timestamp-day result))))))

(deftest test-maybe-instant-integer
  (testing "converts universal time integer"
    (let* ((now (get-universal-time))
           (result (maybe-instant now)))
      (ok (typep result 'local-time:timestamp)))))

(deftest test-maybe-instant-other
  (testing "passes through NIL unchanged"
    (ok (null (maybe-instant nil))))
  (testing "signals error for invalid date strings"
    (ok (signals (maybe-instant "not-a-date")
                 'local-time:invalid-timestring))))

;;; ============================================================
;;; format-timestamp-for-db Tests
;;; ============================================================

(deftest test-format-timestamp-for-db-format
  (testing "formats timestamp for PostgreSQL"
    (let* ((ts (local-time:encode-timestamp 123456 30 15 10 15 1 2024))
           (result (format-timestamp-for-db ts)))
      (ok (stringp result))
      ;; Should be in format: YYYY-MM-DD HH:MM:SS.UUUUUU
      (ok (search "2024-01-15" result))
      (ok (search "10:15:30" result))
      ;; Contains microseconds
      (ok (= 26 (length result))))))

(deftest test-format-timestamp-for-db-zero-padding
  (testing "zero-pads date/time components"
    (let* ((ts (local-time:encode-timestamp 0 5 3 2 5 3 2024))
           (result (format-timestamp-for-db ts)))
      ;; Should have zero-padded month, day, hour, minute, second
      (ok (search "2024-03-05 02:03:05" result)))))
