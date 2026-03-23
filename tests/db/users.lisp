;;;; tests/db/users.lisp --- Tests for user CRUD operations (db/users).

(defpackage #:cl-blog/tests/db/users
  (:use #:cl
        #:rove)
  (:import-from #:cl-blog/tests/support/db
                #:with-test-db)
  (:import-from #:cl-blog/db/users
                #:users-id
                #:users-display-name
                #:users-role
                #:users-password-hash
                #:users-password-salt
                #:create-user!
                #:get-user-by-email
                #:update-user!
                #:delete-user!))

(in-package #:cl-blog/tests/db/users)

;;; ---------------------------------------------------------------------------
;;; Tests
;;; ---------------------------------------------------------------------------

(deftest create-and-fetch-user
  (testing "create-user! persists credentials"
    (with-test-db
      (let* ((created (create-user! :email "user@example.com"
                                    :display-name "Example User"
                                    :password-hash "hash"
                                    :password-salt "salt"
                                    :role "user"))
             (fetched (get-user-by-email "user@example.com")))
        (ok (users-id created))
        (ok (equal (users-id created) (users-id fetched)))
        (ok (equal "Example User" (users-display-name fetched)))
        (ok (equal "user" (users-role fetched)))
        (ok (equal "hash" (users-password-hash fetched)))
        (ok (equal "salt" (users-password-salt fetched)))))))

(deftest update-user-test
  (testing "update-user! refreshes mutable fields"
    (with-test-db
      (let* ((created (create-user! :email "change@example.com"
                                    :display-name "Original"
                                    :password-hash "hash"
                                    :password-salt "salt"
                                    :role "user"))
             (updated (update-user! (users-id created)
                                    :display-name "Updated"
                                    :role "admin")))
        (ok (equal "Updated" (users-display-name updated)))
        (ok (equal "admin" (users-role updated)))))))

(deftest delete-user-test
  (testing "delete-user! removes row"
    (with-test-db
      (create-user! :email "delete@example.com"
                    :display-name "Delete"
                    :password-hash "hash"
                    :password-salt "salt"
                    :role "user")
      (ok (eq t (delete-user! "delete@example.com")))
      (ok (null (delete-user! "delete@example.com")))
      (ok (null (get-user-by-email "delete@example.com"))))))
