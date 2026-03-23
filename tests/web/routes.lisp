(defpackage #:cl-blog/tests/web/routes
  (:use #:cl
        #:rove)
  (:import-from #:cl-blog/tests/support/db
                #:with-test-db)
  (:import-from #:cl-blog/web/routes
                #:root-handler
                #:login-handler
                #:login-page-handler
                #:logout-handler
                #:account-page-handler
                #:account-update-handler
                #:get-param
                ;; Pagination helpers
                #:parse-page-param
                #:make-pagination)
  (:import-from #:cl-blog/web/auth
                #:authenticate
                #:ensure-default-admin!
                #:register!)
  (:import-from #:cl-blog/db/users
                #:delete-user!
                #:get-user-by-id
                #:users-display-name
                #:users-language
                #:users-timezone))

(in-package #:cl-blog/tests/web/routes)

;;; Test helpers

(defmacro with-mock-session (session-hash &body body)
  "Execute BODY with ningle/context:*session* bound to SESSION-HASH."
  `(let ((ningle/context:*session* ,session-hash))
     ,@body))

(defun make-session (&key user)
  "Create a session hash table with optional user."
  (let ((ht (make-hash-table)))
    (when user
      (setf (gethash :user ht) user))
    ht))

(defun response-status (response)
  "Extract status code from response."
  (first response))

(defun response-headers (response)
  "Extract headers from response."
  (second response))

(defun response-body (response)
  "Extract body from response."
  (third response))

(defun response-location (response)
  "Extract Location header from response."
  (getf (response-headers response) :location))

;;; Tests

(deftest root-handler-redirects-based-on-session
  (testing "root redirects unauthenticated users to /login"
    (with-mock-session (make-session)
      (let ((response (root-handler nil)))
        (ok (= 302 (response-status response)))
        (ok (string= "/login" (response-location response))))))

  (testing "root redirects authenticated users to /posts"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      (let ((response (root-handler nil)))
        (ok (= 302 (response-status response)))
        (ok (string= "/posts" (response-location response)))))))

(deftest login-handler-success
  (testing "valid credentials redirect to posts and store user in session"
    (with-test-db
      (ensure-default-admin!)
      (with-mock-session (make-session)
        (let* ((params '(("email" . "admin@cl-blog.dev")
                         ("password" . "changeme")))
               (response (login-handler params)))
          (ok (= 302 (response-status response)))
          (ok (string= "/posts" (response-location response)))
          ;; Session should have user
          (ok (gethash :user ningle/context:*session*))
          (ok (string= "admin@cl-blog.dev"
                       (getf (gethash :user ningle/context:*session*) :email))))))))


(deftest login-handler-failure
  (testing "invalid credentials render login page with error and return 401"
    (with-test-db
      (ensure-default-admin!)
      (with-mock-session (make-session)
        (let* ((params '(("email" . "admin@cl-blog.dev")
                         ("password" . "wrongpassword")))
               (response (login-handler params)))
          (ok (= 401 (response-status response)))
          (ok (search "Invalid email or password"
                      (first (response-body response)))))))))


(deftest logout-handler-clears-session
  (testing "logout clears session and redirects to login"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      ;; Before logout, session has user
      (ok (gethash :user ningle/context:*session*))
      (let ((response (logout-handler nil)))
        (ok (= 302 (response-status response)))
        (ok (string= "/login" (response-location response)))
        ;; After logout, session should be empty
        (ok (zerop (hash-table-count ningle/context:*session*)))))))


(deftest account-page-requires-authentication
  (testing "account page redirects anonymous users to login"
    (with-mock-session (make-session)
      (let ((response (account-page-handler nil)))
        (ok (= 302 (response-status response)))
        (ok (string= "/login" (response-location response)))))))


(deftest account-page-renders-for-authenticated-user
  (testing "account page renders for authenticated user"
    (with-test-db
      (ensure-default-admin!)
      (let ((user (authenticate "admin@cl-blog.dev" "changeme")))
        (with-mock-session (make-session :user user)
          (let ((response (account-page-handler nil)))
            (ok (= 200 (response-status response)))
            ;; Should include user email in the rendered page
            (ok (search "admin@cl-blog.dev" (first (response-body response))))))))))


(deftest account-update-validates-display-name
  (testing "account update rejects blank display name"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      (let* ((params '(("display-name" . "  ")))
             (response (account-update-handler params)))
        (ok (= 302 (response-status response)))
        (ok (search "error" (response-location response))))))

  (testing "account update accepts valid display name"
    (with-test-db
      (let ((user (create-test-user)))
        (unwind-protect
             (with-mock-session (make-session :user user)
               (let* ((params '(("display-name" . "New Name")
                                ("language" . "en")
                                ("timezone" . "UTC")))
                      (response (account-update-handler params)))
                 (ok (= 302 (response-status response)))
                 (ok (search "message" (response-location response)))
                 ;; Session user should have updated name
                 (ok (string= "New Name"
                              (getf (gethash :user ningle/context:*session*) :name)))))
          (ignore-errors (delete-user! (getf user :email))))))))


(deftest login-page-redirects-if-already-authenticated
  (testing "login page redirects authenticated users to posts"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      (let ((response (login-page-handler nil)))
        (ok (= 302 (response-status response)))
        (ok (string= "/posts" (response-location response)))))))


(deftest get-param-extracts-values
  (testing "get-param extracts values from params alist"
    (let ((params '(("email" . "test@example.com")
                    ("password" . "secret"))))
      (ok (string= "test@example.com" (get-param params "email")))
      (ok (string= "secret" (get-param params "password")))
      (ok (null (get-param params "missing"))))))

;;; ---------------------------------------------------------------------------
;;; Integration Tests (with real database)
;;; ---------------------------------------------------------------------------

(defun create-test-user ()
  "Create a test user and return user plist for session."
  (let* ((email (format nil "test-~A@example.com" (uuid:make-v4-uuid)))
         (result (register! :email email
                            :password "testpass123"
                            :name "Test User")))
    (if (eq :ok (first result))
        (let ((user-data (second result)))
          (list :id (getf user-data :id)
                :email email
                :name "Test User"))
        (error "Failed to create test user: ~A" (second result)))))

;;; ---------------------------------------------------------------------------
;;; Account Update Integration Tests
;;; ---------------------------------------------------------------------------

(deftest account-update-persists-to-database
  (testing "account update saves display name to database"
    (with-test-db
      (let ((user (create-test-user)))
        (unwind-protect
             (with-mock-session (make-session :user user)
               (let* ((params '(("display-name" . "Updated Name")
                                ("language" . "en")
                                ("timezone" . "UTC")))
                      (response (account-update-handler params)))
                 ;; Should redirect with success message
                 (ok (= 302 (response-status response)))
                 (ok (search "message" (response-location response)))
                 ;; Verify session updated
                 (let ((session-user (gethash :user ningle/context:*session*)))
                   (ok (string= "Updated Name" (getf session-user :name))))
                 ;; Verify database updated
                 (let ((db-user (get-user-by-id (getf user :id))))
                   (ok db-user "User should exist in database")
                   (ok (string= "Updated Name" (users-display-name db-user))))))
          (ignore-errors (delete-user! (getf user :email))))))))

(deftest account-update-saves-language-setting
  (testing "account update saves language preference to database"
    (with-test-db
      (let ((user (create-test-user)))
        (unwind-protect
             (with-mock-session (make-session :user user)
               (let* ((params '(("display-name" . "Test User")
                                ("language" . "ja")
                                ("timezone" . "UTC")))
                      (response (account-update-handler params)))
                 (ok (= 302 (response-status response)))
                 ;; Verify session updated
                 (let ((session-user (gethash :user ningle/context:*session*)))
                   (ok (string= "ja" (getf session-user :language))))
                 ;; Verify database updated
                 (let ((db-user (get-user-by-id (getf user :id))))
                   (ok (string= "ja" (users-language db-user))))))
          (ignore-errors (delete-user! (getf user :email))))))))

(deftest account-update-saves-timezone-setting
  (testing "account update saves timezone preference to database"
    (with-test-db
      (let ((user (create-test-user)))
        (unwind-protect
             (with-mock-session (make-session :user user)
               (let* ((params '(("display-name" . "Test User")
                                ("language" . "en")
                                ("timezone" . "Asia/Tokyo")))
                      (response (account-update-handler params)))
                 (ok (= 302 (response-status response)))
                 ;; Verify session updated
                 (let ((session-user (gethash :user ningle/context:*session*)))
                   (ok (string= "Asia/Tokyo" (getf session-user :timezone))))
                 ;; Verify database updated
                 (let ((db-user (get-user-by-id (getf user :id))))
                   (ok (string= "Asia/Tokyo" (users-timezone db-user))))))
          (ignore-errors (delete-user! (getf user :email))))))))

(deftest account-update-saves-all-settings-together
  (testing "account update saves all settings (display name, language, timezone) together"
    (with-test-db
      (let ((user (create-test-user)))
        (unwind-protect
             (with-mock-session (make-session :user user)
               (let* ((params '(("display-name" . "New Display Name")
                                ("language" . "ko")
                                ("timezone" . "Asia/Seoul")))
                      (response (account-update-handler params)))
                 (ok (= 302 (response-status response)))
                 (ok (search "message=Settings" (response-location response)))
                 ;; Verify all session fields updated
                 (let ((session-user (gethash :user ningle/context:*session*)))
                   (ok (string= "New Display Name" (getf session-user :name)))
                   (ok (string= "ko" (getf session-user :language)))
                   (ok (string= "Asia/Seoul" (getf session-user :timezone))))
                 ;; Verify all database fields updated
                 (let ((db-user (get-user-by-id (getf user :id))))
                   (ok (string= "New Display Name" (users-display-name db-user)))
                   (ok (string= "ko" (users-language db-user)))
                   (ok (string= "Asia/Seoul" (users-timezone db-user))))))
          (ignore-errors (delete-user! (getf user :email))))))))

(deftest account-page-displays-saved-settings
  (testing "account page displays previously saved language and timezone"
    (with-test-db
      (let ((user (create-test-user)))
        (unwind-protect
             (progn
               ;; First update the settings
               (with-mock-session (make-session :user user)
                 (account-update-handler '(("display-name" . "Test User")
                                           ("language" . "fr")
                                           ("timezone" . "Europe/Paris"))))
               ;; Re-authenticate to get fresh user data with saved settings
               (let* ((fresh-user (authenticate (getf user :email) "testpass123")))
                 (with-mock-session (make-session :user fresh-user)
                   (let ((response (account-page-handler nil)))
                     (ok (= 200 (response-status response)))
                     (let ((body (first (response-body response))))
                       ;; Check that the saved language is selected
                       (ok (search "value=fr selected" body)
                           "French should be selected in language dropdown")
                       ;; Check that the saved timezone is selected (has quotes due to /)
                       (ok (search "value=\"Europe/Paris\" selected" body)
                           "Europe/Paris should be selected in timezone dropdown"))))))
          (ignore-errors (delete-user! (getf user :email))))))))

;;; ---------------------------------------------------------------------------
;;; Pagination Helper Tests
;;; ---------------------------------------------------------------------------

(deftest parse-page-param-returns-valid-page
  (testing "parse-page-param returns valid page numbers"
    (ok (= 1 (parse-page-param '(("page" . "1")))))
    (ok (= 5 (parse-page-param '(("page" . "5")))))
    (ok (= 100 (parse-page-param '(("page" . "100")))))))

(deftest parse-page-param-returns-1-for-invalid
  (testing "parse-page-param returns 1 for invalid input"
    ;; No page param
    (ok (= 1 (parse-page-param '())))
    (ok (= 1 (parse-page-param nil)))
    ;; Non-numeric
    (ok (= 1 (parse-page-param '(("page" . "abc")))))
    (ok (= 1 (parse-page-param '(("page" . "")))))
    ;; Zero or negative
    (ok (= 1 (parse-page-param '(("page" . "0")))))
    (ok (= 1 (parse-page-param '(("page" . "-1")))))))

(deftest make-pagination-returns-correct-info
  (testing "make-pagination returns correct pagination info"
    (let ((pag (make-pagination 1 10 5 "/test")))
      (ok (= 1 (getf pag :current-page)))
      (ok (= 2 (getf pag :total-pages)))
      (ok (= 10 (getf pag :total-count)))
      (ok (null (getf pag :has-prev)))
      (ok (getf pag :has-next))
      (ok (null (getf pag :prev-url)))
      (ok (string= "/test?page=2" (getf pag :next-url))))))

(deftest make-pagination-last-page
  (testing "make-pagination handles last page correctly"
    (let ((pag (make-pagination 3 15 5 "/items")))
      (ok (= 3 (getf pag :current-page)))
      (ok (= 3 (getf pag :total-pages)))
      (ok (getf pag :has-prev))
      (ok (null (getf pag :has-next)))
      (ok (string= "/items?page=2" (getf pag :prev-url)))
      (ok (null (getf pag :next-url))))))

(deftest make-pagination-middle-page
  (testing "make-pagination handles middle page correctly"
    (let ((pag (make-pagination 2 15 5 "/data")))
      (ok (= 2 (getf pag :current-page)))
      (ok (= 3 (getf pag :total-pages)))
      (ok (getf pag :has-prev))
      (ok (getf pag :has-next))
      (ok (string= "/data?page=1" (getf pag :prev-url)))
      (ok (string= "/data?page=3" (getf pag :next-url))))))

(deftest make-pagination-single-page
  (testing "make-pagination handles single page correctly"
    (let ((pag (make-pagination 1 3 5 "/single")))
      (ok (= 1 (getf pag :current-page)))
      (ok (= 1 (getf pag :total-pages)))
      (ok (null (getf pag :has-prev)))
      (ok (null (getf pag :has-next)))
      (ok (null (getf pag :prev-url)))
      (ok (null (getf pag :next-url))))))

(deftest make-pagination-empty-data
  (testing "make-pagination handles empty data correctly"
    (let ((pag (make-pagination 1 0 5 "/empty")))
      (ok (= 1 (getf pag :current-page)))
      (ok (= 1 (getf pag :total-pages)))
      (ok (null (getf pag :has-prev)))
      (ok (null (getf pag :has-next))))))
