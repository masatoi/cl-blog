;;;; tests/utils/common.lisp --- Tests for shared utility functions (utils/common).

(defpackage #:cl-blog/tests/utils/common
  (:use #:cl #:rove)
  (:import-from #:cl-blog/utils/common
                #:generate-uuid
                #:trim-whitespace
                #:blank-string-p
                #:normalize-string
                #:parse-json
                #:json->string))

(in-package #:cl-blog/tests/utils/common)

;;; ============================================================
;;; UUID Tests
;;; ============================================================

(deftest test-generate-uuid-format
  (testing "generates valid UUID v4 format"
    (let ((uuid (generate-uuid)))
      (ok (stringp uuid))
      ;; UUID format: 8-4-4-4-12 hex chars
      (ok (= 36 (length uuid)))
      ;; Check hyphen positions
      (ok (char= #\- (char uuid 8)))
      (ok (char= #\- (char uuid 13)))
      (ok (char= #\- (char uuid 18)))
      (ok (char= #\- (char uuid 23)))
      ;; Verify lowercase
      (ok (string= uuid (string-downcase uuid))))))

(deftest test-generate-uuid-uniqueness
  (testing "generates unique UUIDs"
    (let ((uuids (loop repeat 100 collect (generate-uuid))))
      ;; All should be unique
      (ok (= 100 (length (remove-duplicates uuids :test #'string=)))))))

;;; ============================================================
;;; String Utility Tests
;;; ============================================================

(deftest test-trim-whitespace-basic
  (testing "trims leading and trailing whitespace"
    (ok (equal "hello" (trim-whitespace "  hello  ")))
    (ok (equal "hello" (trim-whitespace "hello")))
    (ok (equal "hello world" (trim-whitespace "  hello world  ")))))

(deftest test-trim-whitespace-various-chars
  (testing "trims various whitespace characters"
    (ok (equal "test" (trim-whitespace (format nil "~C~Ctest~C~C"
                                                #\Tab #\Space #\Newline #\Return))))))

(deftest test-trim-whitespace-empty
  (testing "returns NIL for empty or whitespace-only strings"
    (ok (null (trim-whitespace "")))
    (ok (null (trim-whitespace "   ")))
    (ok (null (trim-whitespace (format nil "~C~C" #\Tab #\Newline))))))

(deftest test-trim-whitespace-nil
  (testing "returns NIL for NIL input"
    (ok (null (trim-whitespace nil)))))

(deftest test-trim-whitespace-non-string
  (testing "returns NIL for non-string input"
    (ok (null (trim-whitespace 123)))
    (ok (null (trim-whitespace :keyword)))
    (ok (null (trim-whitespace '(a b c))))))

(deftest test-blank-string-p-true-cases
  (testing "returns T for blank values"
    (ok (blank-string-p nil))
    (ok (blank-string-p ""))
    (ok (blank-string-p "   "))
    (ok (blank-string-p (format nil "~C~C" #\Tab #\Newline)))
    ;; Non-strings are considered blank
    (ok (blank-string-p 123))
    (ok (blank-string-p :keyword))))

(deftest test-blank-string-p-false-cases
  (testing "returns NIL for non-blank strings"
    (ok (not (blank-string-p "hello")))
    (ok (not (blank-string-p "  x  ")))
    (ok (not (blank-string-p "0")))))

(deftest test-normalize-string-basic
  (testing "trims and lowercases string"
    (ok (equal "hello" (normalize-string "  HELLO  ")))
    (ok (equal "hello world" (normalize-string "  Hello World  ")))))

(deftest test-normalize-string-empty
  (testing "returns NIL for blank input"
    (ok (null (normalize-string nil)))
    (ok (null (normalize-string "")))
    (ok (null (normalize-string "   ")))))

;;; ============================================================
;;; JSON Utility Tests
;;; ============================================================

(deftest test-parse-json-object
  (testing "parses JSON object to hash-table"
    (let ((result (parse-json "{\"name\": \"Alice\", \"age\": 30}")))
      (ok (hash-table-p result))
      (ok (equal "Alice" (gethash "name" result)))
      (ok (= 30 (gethash "age" result))))))

(deftest test-parse-json-array
  (testing "parses JSON array to vector"
    (let ((result (parse-json "[1, 2, 3]")))
      (ok (vectorp result))
      (ok (equalp #(1 2 3) result)))))

(deftest test-parse-json-primitives
  (testing "parses JSON primitives"
    (ok (equal "hello" (parse-json "\"hello\"")))
    (ok (= 42 (parse-json "42")))
    ;; JSON numbers are parsed as double-float
    (ok (= 3.14d0 (parse-json "3.14")))
    (ok (eq t (parse-json "true")))
    (ok (eq nil (parse-json "false")))
    ;; jzon parses null as the symbol NULL (in CL package), not NIL
    (ok (or (null (parse-json "null"))
            (eq :null (parse-json "null"))
            (eq 'null (parse-json "null"))))))

(deftest test-parse-json-nil-input
  (testing "returns NIL for NIL or empty input"
    (ok (null (parse-json nil)))
    (ok (null (parse-json "")))
    (ok (null (parse-json 123)))))

(deftest test-parse-json-invalid
  (testing "returns NIL for invalid JSON"
    (ok (null (parse-json "not json")))
    (ok (null (parse-json "{invalid}")))))

(deftest test-json->string-object
  (testing "serializes hash-table to JSON"
    (let* ((ht (make-hash-table :test 'equal))
           (_ (setf (gethash "name" ht) "Bob"))
           (result (json->string ht)))
      (declare (ignore _))
      (ok (stringp result))
      (ok (search "name" result))
      (ok (search "Bob" result)))))

(deftest test-json->string-array
  (testing "serializes vector to JSON array"
    (let ((result (json->string #(1 2 3))))
      (ok (stringp result))
      (ok (search "1" result))
      (ok (search "2" result))
      (ok (search "3" result)))))

(deftest test-json->string-nil
  (testing "returns NIL for NIL input"
    (ok (null (json->string nil)))))

(deftest test-json-roundtrip
  (testing "JSON serialization and parsing roundtrip"
    (let* ((ht (make-hash-table :test 'equal))
           (_ (progn
                (setf (gethash "string" ht) "value")
                (setf (gethash "number" ht) 42)
                (setf (gethash "bool" ht) t)
                (setf (gethash "array" ht) #(1 2 3))))
           (json-str (json->string ht))
           (parsed (parse-json json-str)))
      (declare (ignore _))
      (ok (equal "value" (gethash "string" parsed)))
      (ok (= 42 (gethash "number" parsed)))
      (ok (eq t (gethash "bool" parsed)))
      (ok (equalp #(1 2 3) (gethash "array" parsed))))))
