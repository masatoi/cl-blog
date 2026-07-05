;;;; tests/db/users.lisp --- Tests for user CRUD operations (db/users).

(defpackage #:recurya/tests/db/users
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db)
  (:import-from #:recurya/db/users
                #:users-id
                #:users-email
                #:users-display-name
                #:users-role
                #:users-password-hash
                #:users-password-salt
                #:users-provider
                #:users-provider-uid
                #:create-user!
                #:get-user-by-email
                #:get-user-by-provider
                #:find-or-create-oauth-user
                #:update-user!
                #:delete-user!))

(in-package #:recurya/tests/db/users)

;;; ---------------------------------------------------------------------------
;;; Tests
;;; ---------------------------------------------------------------------------

(deftest create-and-fetch-user
  (testing "create-user! persists credentials"
    (with-test-db
      (let ((created (create-user! :email "user@example.com"
                                   :handle "user-example"
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
                                    :handle "change-user"
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
                    :handle "delete-user"
                    :display-name "Delete"
                    :password-hash "hash"
                    :password-salt "salt"
                    :role "user")
      (ok (eq t (delete-user! "delete@example.com")))
      (ok (null (delete-user! "delete@example.com")))
      (ok (null (get-user-by-email "delete@example.com"))))))

(deftest find-or-create-oauth-user-new
  (testing "creates a new user when neither provider nor email match"
    (with-test-db
      (let ((u (find-or-create-oauth-user :provider "google"
                                          :provider-uid "g-1"
                                          :email "new@example.com"
                                          :display-name "New"
                                          :role "user")))
        (ok (users-id u))
        (ok (equal "google" (users-provider u)))
        (ok (equal "g-1" (users-provider-uid u)))
        (ok (equal "new@example.com" (users-email u)))
        (ok (equal "New" (users-display-name u)))
        (ok (equal "user" (users-role u)))))))

(deftest find-or-create-oauth-user-existing-by-provider
  (testing "returns the same user when (provider, uid) already exists"
    (with-test-db
      (let ((u1 (find-or-create-oauth-user :provider "github"
                                           :provider-uid "gh-9"
                                           :email "a@example.com"
                                           :display-name "A"))
            (u2 (find-or-create-oauth-user :provider "github"
                                           :provider-uid "gh-9"
                                           :email "ignored@example.com"
                                           :display-name "Ignored")))
        (ok (equal (users-id u1) (users-id u2)))
        (ok (equal "a@example.com" (users-email u2)))))))

(deftest find-or-create-oauth-user-merge-by-email
  (testing "links provider to an existing email account when uid is new"
    (with-test-db
      (let ((existing (create-user! :email "shared@example.com"
                                    :handle "shared-user"
                                    :display-name "Shared"
                                    :role "user"))
            (linked (find-or-create-oauth-user :provider "google"
                                               :provider-uid "g-merge"
                                               :email "shared@example.com"
                                               :display-name "Shared (Google)")))
        (ok (equal (users-id existing) (users-id linked)))
        (ok (equal "google" (users-provider linked)))
        (ok (equal "g-merge" (users-provider-uid linked)))
        (ok (equal (users-id linked)
                   (users-id (get-user-by-provider "google" "g-merge"))))))))

(deftest users-handle-required-and-unique
  (testing "handle is required (NOT NULL) at the DB level"
    (with-test-db
      (ok (signals
            (create-user! :email "no-handle@example.com"
                          :display-name "NoHandle"
                          :password-hash "hash"
                          :password-salt "salt"
                          :role "user")
            'error))))
  (testing "handle is unique across users"
    (with-test-db
      (create-user! :email "alice@example.com"
                    :handle "alice"
                    :display-name "Alice"
                    :password-hash "hash"
                    :password-salt "salt"
                    :role "user")
      (ok (signals
            (create-user! :email "bob@example.com"
                          :handle "alice"
                          :display-name "Bob"
                          :password-hash "hash"
                          :password-salt "salt"
                          :role "user")
            'error)))))
