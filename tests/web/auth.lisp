;;;; tests/web/auth.lisp --- Tests for authentication (register, login, hashing).

(defpackage #:cl-blog/tests/web/auth
  (:use #:cl
        #:rove)
  (:import-from #:cl-blog/web/auth
                #:register!
                #:authenticate
                #:ensure-default-admin!
                #:email-exists-p
                #:derive-password
                #:verify-password)
  (:import-from #:cl-blog/db/users
                #:get-user-by-email
                #:users-display-name
                #:users-password-hash
                #:users-id)
  (:import-from #:cl-blog/db/core
                #:start!
                #:stop!))

(in-package #:cl-blog/tests/web/auth)

(defun call-with-test-db (thunk)
  "Set up a fresh test database for each test."
  (stop!)
  (start!)
  (funcall thunk))

(defmacro with-test-db (&body body)
  `(call-with-test-db (lambda () ,@body)))

(deftest register-and-authenticate
  (testing "register! persists hashed credentials and authenticate works"
    (with-test-db
      ;; Register a new user
      (let ((result (register! :email "new@example.com"
                               :password "secret"
                               :name "New User")))
        (ok (listp result))
        (ok (eq :ok (first result)))
        (let ((user-data (second result)))
          (ok (getf user-data :id) "User ID should be present")
          (ok (string= "new@example.com" (getf user-data :email)))))

      ;; Attempting to register with the same email should fail
      (let ((duplicate (register! :email "new@example.com"
                                  :password "secret"
                                  :name "New User")))
        (ok (equal '(:error :email/exists) duplicate)
            "Duplicate email should return :email/exists"))

      ;; Check user was persisted correctly
      (let ((db-user (get-user-by-email "new@example.com")))
        (ok db-user "User should exist in database")
        (ok (string= "New User" (users-display-name db-user))
            "Display name should match")
        (ok (not (string= "secret" (users-password-hash db-user)))
            "Password should be hashed, not stored as plain text")

        ;; Authenticate with correct password
        (let ((authed (authenticate "new@example.com" "secret")))
          (ok authed "Authentication should succeed with correct password")
          (ok (equal (users-id db-user) (getf authed :id))
              "Authenticated user ID should match")
          (ok (string= "new@example.com" (getf authed :email))
              "Authenticated email should match"))

        ;; Authenticate with wrong password should fail
        (ok (null (authenticate "new@example.com" "wrong"))
            "Authentication should fail with wrong password")))))

(deftest ensure-default-admin-creates-admin
  (testing "ensure-default-admin! seeds admin account"
    (with-test-db
      ;; First call should create admin
      (ensure-default-admin!)
      (ok (authenticate "admin@cl-blog.dev" "changeme")
          "Admin should be able to authenticate after first call")

      ;; Second call should be idempotent
      (ensure-default-admin!)
      (ok (authenticate "admin@cl-blog.dev" "changeme")
          "Admin should still authenticate after second call (idempotent)"))))

(deftest register-validation
  (testing "register! validates required fields"
    (with-test-db
      ;; Blank email
      (ok (equal '(:error :email/blank)
                 (register! :email "" :password "secret" :name "User"))
          "Blank email should return :email/blank")
      (ok (equal '(:error :email/blank)
                 (register! :email nil :password "secret" :name "User"))
          "Nil email should return :email/blank")

      ;; Blank password
      (ok (equal '(:error :password/blank)
                 (register! :email "test@example.com" :password "" :name "User"))
          "Blank password should return :password/blank")

      ;; Blank name
      (ok (equal '(:error :name/blank)
                 (register! :email "test@example.com" :password "secret" :name ""))
          "Blank name should return :name/blank"))))

(deftest password-hashing
  (testing "derive-password and verify-password work correctly"
    (let* ((derived (derive-password "mysecret"))
           (salt (getf derived :salt))
           (hash (getf derived :hash)))
      (ok (stringp salt) "Salt should be a string")
      (ok (stringp hash) "Hash should be a string")
      (ok (= 32 (length salt)) "Salt should be 32 hex chars (16 bytes)")
      (ok (= 64 (length hash)) "Hash should be 64 hex chars (32 bytes)")

      ;; Verify with correct password
      (ok (verify-password "mysecret" salt hash)
          "Verify should succeed with correct password")

      ;; Verify with wrong password
      (ok (not (verify-password "wrongpassword" salt hash))
          "Verify should fail with wrong password"))))

(deftest email-normalization
  (testing "email addresses are normalized (lowercase, trimmed)"
    (with-test-db
      (register! :email "  TEST@EXAMPLE.COM  "
                 :password "secret"
                 :name "Test User")

      ;; Should find user with normalized email
      (ok (email-exists-p "test@example.com")
          "Should find user with lowercase email")
      (ok (email-exists-p "TEST@EXAMPLE.COM")
          "Should find user with uppercase email")
      (ok (email-exists-p "  test@example.com  ")
          "Should find user with whitespace-padded email")

      ;; Should authenticate with any case
      (ok (authenticate "TEST@EXAMPLE.COM" "secret")
          "Should authenticate with uppercase email")
      (ok (authenticate "test@example.com" "secret")
          "Should authenticate with lowercase email"))))
