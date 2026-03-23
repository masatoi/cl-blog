(defpackage #:cl-blog/tests/db/jsonb
  (:use #:cl #:rove)
  (:import-from #:cl-blog/db/jsonb
                #:normalize-sql-key
                #:sql-getf
                #:sql-result-value
                #:jsonb->lisp
                #:lisp->jsonb
                #:json-get
                #:json-get-string
                #:json-get-number
                #:json-get-list
                #:json-get-bool
                #:json-keys
                #:json-values
                #:map-json))

(in-package #:cl-blog/tests/db/jsonb)

;;; ============================================================
;;; SQL Key Normalization Tests
;;; ============================================================

(deftest test-normalize-sql-key-uppercase
  (testing "normalizes uppercase keywords"
    (ok (eq :JOB-COUNT (normalize-sql-key :JOB_COUNT)))
    (ok (eq :VERSION (normalize-sql-key :VERSION)))))

(deftest test-normalize-sql-key-pipe-case
  (testing "normalizes pipe-quoted keywords"
    (ok (eq :JOB-COUNT (normalize-sql-key :|job_count|)))
    (ok (eq :VERSION (normalize-sql-key :|version|)))))

(deftest test-normalize-sql-key-mixed
  (testing "normalizes mixed case strings"
    (ok (eq :JOB-COUNT (normalize-sql-key "job_count")))
    (ok (eq :JOB-COUNT (normalize-sql-key "Job_Count")))))

(deftest test-sql-getf-basic
  (testing "retrieves values with key normalization"
    (let ((plist '(:JOB-COUNT 5 :VERSION 3)))
      (ok (= 5 (sql-getf plist :job-count)))
      (ok (= 5 (sql-getf plist :job_count)))
      (ok (= 3 (sql-getf plist :version))))))

(deftest test-sql-getf-pipe-case
  (testing "retrieves from pipe-case plists"
    (let ((plist '(:|job_count| 10 :|version| 2)))
      (ok (= 10 (sql-getf plist :job-count)))
      (ok (= 10 (sql-getf plist :JOB_COUNT)))
      (ok (= 2 (sql-getf plist :version))))))

(deftest test-sql-getf-default
  (testing "returns default when key not found"
    (let ((plist '(:FOO 1)))
      (ok (null (sql-getf plist :bar)))
      (ok (= 42 (sql-getf plist :bar 42))))))

(deftest test-sql-result-value-nil-row
  (testing "handles NIL row gracefully"
    (ok (null (sql-result-value nil :key)))
    (ok (= 0 (sql-result-value nil :key 0)))))

;;; ============================================================
;;; JSONB Column Helpers Tests
;;; ============================================================

(deftest test-jsonb->lisp-string
  (testing "parses JSON string"
    (let ((result (jsonb->lisp "{\"name\": \"test\", \"count\": 42}")))
      (ok (hash-table-p result))
      (ok (equal "test" (gethash "name" result)))
      (ok (= 42 (gethash "count" result))))))

(deftest test-jsonb->lisp-hash-table
  (testing "passes through hash-table"
    (let* ((ht (make-hash-table :test 'equal))
           (_ (setf (gethash "key" ht) "value"))
           (result (jsonb->lisp ht)))
      (declare (ignore _))
      (ok (eq ht result)))))

(deftest test-jsonb->lisp-vector
  (testing "passes through vector"
    (let* ((vec #(1 2 3))
           (result (jsonb->lisp vec)))
      (ok (eq vec result)))))

(deftest test-jsonb->lisp-nil
  (testing "handles NIL and empty"
    (ok (null (jsonb->lisp nil)))
    (ok (null (jsonb->lisp "")))
    (ok (null (jsonb->lisp "   ")))))

(deftest test-jsonb->lisp-invalid
  (testing "handles invalid JSON gracefully"
    (ok (null (jsonb->lisp "not json")))
    (ok (null (jsonb->lisp "{invalid}")))))

(deftest test-lisp->jsonb-basic
  (testing "serializes to JSON string"
    (let* ((ht (make-hash-table :test 'equal))
           (_ (setf (gethash "name" ht) "test"))
           (result (lisp->jsonb ht)))
      (declare (ignore _))
      (ok (stringp result))
      (ok (search "name" result))
      (ok (search "test" result)))))

(deftest test-lisp->jsonb-nil
  (testing "returns NIL for NIL input"
    (ok (null (lisp->jsonb nil)))))

;;; ============================================================
;;; Type-Safe JSON Accessors Tests
;;; ============================================================

(deftest test-json-get-from-hash-table
  (testing "gets value from hash-table"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "name" ht) "Alice")
      (setf (gethash "age" ht) 30)
      (ok (equal "Alice" (json-get ht :name)))
      (ok (equal "Alice" (json-get ht "name")))
      (ok (= 30 (json-get ht :age))))))

(deftest test-json-get-from-string
  (testing "gets value from JSON string"
    (let ((json "{\"name\": \"Bob\", \"active\": true}"))
      (ok (equal "Bob" (json-get json :name)))
      (ok (eq t (json-get json :active))))))

(deftest test-json-get-default
  (testing "returns default for missing key"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "foo" ht) "bar")
      (ok (null (json-get ht :missing)))
      (ok (equal "default" (json-get ht :missing "default"))))))

(deftest test-json-get-string
  (testing "gets string values"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "name" ht) "Alice")
      (setf (gethash "age" ht) 30)
      (ok (equal "Alice" (json-get-string ht :name)))
      (ok (null (json-get-string ht :age)))
      (ok (equal "default" (json-get-string ht :age "default"))))))

(deftest test-json-get-number
  (testing "gets number values"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "count" ht) 42)
      (setf (gethash "name" ht) "test")
      (ok (= 42 (json-get-number ht :count)))
      (ok (null (json-get-number ht :name)))
      (ok (= 0 (json-get-number ht :name 0))))))

(deftest test-json-get-list-from-vector
  (testing "converts vector to list"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "items" ht) #("a" "b" "c"))
      (let ((result (json-get-list ht :items)))
        (ok (listp result))
        (ok (equal '("a" "b" "c") result))))))

(deftest test-json-get-list-from-json-string
  (testing "parses JSON array from string"
    (let ((json "{\"labels\": [\"cat\", \"dog\", \"bird\"]}"))
      (let ((result (json-get-list json :labels)))
        (ok (listp result))
        (ok (equal '("cat" "dog" "bird") result))))))

(deftest test-json-get-bool
  (testing "gets boolean values"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "active" ht) t)
      (setf (gethash "deleted" ht) nil)
      (ok (eq t (json-get-bool ht :active)))
      (ok (eq nil (json-get-bool ht :deleted))))))

;;; ============================================================
;;; Iteration Helpers Tests
;;; ============================================================

(deftest test-json-keys
  (testing "returns all keys"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "a" ht) 1)
      (setf (gethash "b" ht) 2)
      (let ((keys (json-keys ht)))
        (ok (= 2 (length keys)))
        (ok (member "a" keys :test #'equal))
        (ok (member "b" keys :test #'equal))))))

(deftest test-json-keys-from-string
  (testing "returns keys from JSON string"
    (let ((keys (json-keys "{\"x\": 1, \"y\": 2}")))
      (ok (= 2 (length keys)))
      (ok (member "x" keys :test #'equal))
      (ok (member "y" keys :test #'equal)))))

(deftest test-json-values
  (testing "returns all values"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "a" ht) 1)
      (setf (gethash "b" ht) 2)
      (let ((values (json-values ht)))
        (ok (= 2 (length values)))
        (ok (member 1 values))
        (ok (member 2 values))))))

(deftest test-map-json
  (testing "maps over key-value pairs"
    (let ((ht (make-hash-table :test 'equal)))
      (setf (gethash "a" ht) 1)
      (setf (gethash "b" ht) 2)
      (let ((result (map-json (lambda (k v) (cons k v)) ht)))
        (ok (= 2 (length result)))
        (ok (member '("a" . 1) result :test #'equal))
        (ok (member '("b" . 2) result :test #'equal))))))
