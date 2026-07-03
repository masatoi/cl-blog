;;;; tests/web/routes.lisp --- Tests for route handlers and HTMX interactions.

(defpackage #:recurya/tests/web/routes
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db)
  (:import-from #:recurya/web/routes
                #:root-handler
                #:dashboard-home-handler
                #:login-page-handler
                #:logout-handler
                #:account-page-handler
                #:account-update-handler
                #:account-confirm-delete-handler
                #:account-delete-handler
                #:get-param
                ;; Pagination helpers
                #:parse-page-param
                #:make-pagination)
  (:import-from #:recurya/db/users
                #:find-or-create-oauth-user
                #:delete-user!
                #:get-user-by-id
                #:users-display-name
                #:users-language
                #:users-timezone))

(in-package #:recurya/tests/web/routes)

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
  (testing "anonymous GET / -> 302 /notebooks"
    (with-mock-session (make-session)
      (let ((response (root-handler nil)))
        (ok (= 302 (response-status response)))
        (ok (string= "/notebooks" (response-location response))))))

  (testing "logged-in GET / -> 302 /dashboard"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      (let ((response (root-handler nil)))
        (ok (= 302 (response-status response)))
        (ok (string= "/dashboard" (response-location response)))))))

(deftest dashboard-home-redirects-to-notebooks
  (testing "GET /dashboard redirects to /dashboard/notebooks"
    (let ((response (dashboard-home-handler nil)))
      (ok (= 302 (response-status response)))
      (ok (string= "/dashboard/notebooks" (response-location response))))))

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
      (let ((user (create-test-user)))
        (unwind-protect
             (with-mock-session (make-session :user user)
               (let ((response (account-page-handler nil)))
                 (ok (= 200 (response-status response)))
                 (ok (search (getf user :email) (first (response-body response))))))
          (ignore-errors (delete-user! (getf user :email))))))))

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
  (testing "login page redirects authenticated users to /dashboard/notebooks"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      (let ((response (login-page-handler nil)))
        (ok (= 302 (response-status response)))
        (ok (string= "/dashboard/notebooks" (response-location response)))))))

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
  "Create a test user via the OAuth find-or-create path and return user plist."
  (let* ((uuid (uuid:make-v4-uuid))
         (uid (format nil "test-~A" uuid))
         (email (format nil "test-~A@example.com" uuid))
         (dao (find-or-create-oauth-user :provider "google"
                                         :provider-uid uid
                                         :email email
                                         :display-name "Test User"
                                         :role "user")))
    (list :id (recurya/models/users:users-id dao)
          :email email
          :name "Test User"
          :role :user
          :provider "google"
          :language (recurya/models/users:users-language dao)
          :timezone (recurya/models/users:users-timezone dao))))

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
               (with-mock-session (make-session :user user)
                 (account-update-handler '(("display-name" . "Test User")
                                           ("language" . "fr")
                                           ("timezone" . "Europe/Paris"))))
               (let* ((db-user (get-user-by-id (getf user :id)))
                      (fresh-user (list :id (recurya/models/users:users-id db-user)
                                        :email (recurya/models/users:users-email db-user)
                                        :name (recurya/models/users:users-display-name db-user)
                                        :role (intern (string-upcase (recurya/models/users:users-role db-user)) :keyword)
                                        :language (recurya/models/users:users-language db-user)
                                        :timezone (recurya/models/users:users-timezone db-user))))
                 (with-mock-session (make-session :user fresh-user)
                   (let ((response (account-page-handler nil)))
                     (ok (= 200 (response-status response)))
                     (let ((body (first (response-body response))))
                       (ok (search "value=fr selected" body)
                           "French should be selected in language dropdown")
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

(deftest admin-email-promotion-from-env
  (testing "admin-email-p matches lower-cased entries from ADMIN_OAUTH_EMAIL"
    (let ((saved (uiop:getenv "ADMIN_OAUTH_EMAIL")))
      (unwind-protect
           (progn
             (setf (uiop:getenv "ADMIN_OAUTH_EMAIL")
                   "Boss@Example.com, other@example.com")
             (ok (recurya/web/routes::admin-email-p "boss@example.com"))
             (ok (recurya/web/routes::admin-email-p "BOSS@example.com"))
             (ok (recurya/web/routes::admin-email-p "other@example.com"))
             (ok (null (recurya/web/routes::admin-email-p "stranger@example.com")))
             (ok (null (recurya/web/routes::admin-email-p nil))))
        (setf (uiop:getenv "ADMIN_OAUTH_EMAIL") (or saved ""))))))

(deftest header-logged-in-links-to-dashboard-notebooks-and-courses
  (testing "The logged-in header's user menu links to both My Notebooks
(/dashboard/notebooks) and My Courses (/dashboard/courses), so the course
management UI is reachable from every page — not only /dashboard/notebooks."
    (let ((user (list :id "u1" :name "Tester" :handle "tester")))
      (with-mock-session (make-session :user user)
        (let ((body (recurya/web/ui/layout:header user)))
          (ok (search "/dashboard/notebooks" body)
              "My Notebooks link present in the logged-in header")
          (ok (search "/dashboard/courses" body)
              "My Courses link present in the logged-in header"))))))

;;; ---------------------------------------------------------------------------
;;; HTMX Confirmation Modal Tests
;;; ---------------------------------------------------------------------------

(defmacro with-mock-request ((&key htmx) &body body)
  "Execute BODY with a mock Lack request bound to ningle/context:*request*.
When HTMX is true, the HX-Request header is present."
  `(let* ((headers (make-hash-table :test 'equal))
          (env (append (list :request-method :get
                             :path-info "/test"
                             :headers headers)
                       (when ,htmx (list :http-hx-request "true"))))
          (ningle/context:*request* (lack/request:make-request env)))
     ,@body))

(deftest render-confirm-modal-generates-correct-html
  (testing "render-confirm-modal produces modal overlay with HTMX attributes"
    (let ((html (recurya/web/routes::render-confirm-modal
                 :title "Delete?"
                 :message "Are you sure?"
                 :confirm-hx-post "/items/1/delete"
                 :confirm-label "Confirm")))
      (ok (search "modal-overlay" html) "Contains modal-overlay class")
      (ok (search "modal-card" html) "Contains modal-card class")
      (ok (search "Delete?" html) "Contains title")
      (ok (search "Are you sure?" html) "Contains message")
      (ok (search "hx-post=\"/items/1/delete\"" html) "Contains hx-post on confirm button")
      (ok (search "Confirm" html) "Contains confirm label")
      (ok (search "Cancel" html) "Contains cancel button")))

  (testing "render-confirm-modal uses custom target and swap"
    (let ((html (recurya/web/routes::render-confirm-modal
                 :title "Delete?"
                 :message "Sure?"
                 :confirm-hx-post "/x"
                 :confirm-hx-target "#row-1"
                 :confirm-hx-swap "outerHTML swap:0.3s")))
      (ok (search "hx-target=#row-1" html) "Contains custom hx-target")
      (ok (search "outerHTML swap:0.3s" html) "Contains custom hx-swap"))))

(deftest account-confirm-delete-requires-auth
  (testing "returns 401 when not authenticated"
    (with-mock-session (make-session)
      (let ((response (account-confirm-delete-handler nil)))
        (ok (= 401 (response-status response)))))))

(deftest account-confirm-delete-returns-modal-fragment
  (testing "returns modal HTML with correct HTMX attributes"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      (let* ((response (account-confirm-delete-handler nil))
             (body (first (response-body response))))
        (ok (= 200 (response-status response)))
        (ok (search "modal-overlay" body) "Contains modal overlay")
        (ok (search "Delete your account?" body) "Contains title")
        (ok (search "hx-post=\"/account/delete\"" body)
            "Confirm button posts to /account/delete")
        (ok (search "Delete account" body) "Confirm label is 'Delete account'")))))

(deftest account-delete-returns-hx-redirect-for-htmx
  (testing "HTMX account delete returns HX-Redirect header"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      (with-mock-request (:htmx t)
        (let ((response (account-delete-handler nil)))
          (ok (= 200 (response-status response)))
          (ok (string= "/login"
                       (getf (response-headers response) :hx-redirect))
              "HX-Redirect header points to /login")))))

  (testing "non-HTMX account delete redirects normally"
    (with-mock-session (make-session :user '(:id "123" :email "test@example.com"))
      (with-mock-request (:htmx nil)
        (let ((response (account-delete-handler nil)))
          (ok (= 302 (response-status response)))
          (ok (string= "/login" (response-location response))))))))
