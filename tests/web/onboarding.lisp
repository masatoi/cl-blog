;;;; tests/web/onboarding.lisp --- Tests for the handle onboarding flow.
;;;;
;;;; Covers:
;;;;   * GET /onboarding/handle for placeholder, real, and anonymous users.
;;;;   * POST /onboarding/handle validation (format, reserved, taken).
;;;;   * Successful POST persists to DB and refreshes session.
;;;;   * The require-real-handle middleware: redirects placeholder users
;;;;     away from protected paths, lets the onboarding form through, and
;;;;     does not interfere with users that already have a real handle.

(defpackage #:recurya/tests/web/onboarding
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db
                #:create-test-user)
  (:import-from #:recurya/web/routes
                #:onboarding-handle-page-handler
                #:onboarding-handle-create-handler)
  (:import-from #:recurya/web/auth
                #:require-real-handle)
  (:import-from #:recurya/db/users
                #:placeholder-handle-p
                #:get-user-by-id
                #:users-id
                #:users-handle
                #:users-display-name
                #:users-email))

(in-package #:recurya/tests/web/onboarding)

;;; --- Helpers --------------------------------------------------------------

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

(defun response-status (response) (first response))
(defun response-headers (response) (second response))
(defun response-body (response) (third response))
(defun response-location (response)
  (getf (response-headers response) :location))

(defun mk-user-plist (dao &key (handle (users-handle dao)))
  "Build the session plist shape for a USERS dao."
  (list :id (users-id dao)
        :email (users-email dao)
        :name (users-display-name dao)
        :handle handle
        :role :user
        :provider "google"
        :timezone "UTC"
        :language "en"))

;;; --- Predicate ------------------------------------------------------------

(deftest placeholder-handle-p-detection
  (testing "matches Phase-5 placeholders"
    (ok (placeholder-handle-p "u-1a2b3c4d"))
    (ok (placeholder-handle-p "u-deadbeef"))
    (ok (placeholder-handle-p "u-00000000")))
  (testing "rejects real handles"
    (ng (placeholder-handle-p "alice"))
    (ng (placeholder-handle-p "bob-the-builder"))
    (ng (placeholder-handle-p "u-")) ; too short
    (ng (placeholder-handle-p "u-1a2b3c4")) ; only 7 hex chars
    (ng (placeholder-handle-p "u-1a2b3c4d5")) ; 9 hex chars
    (ng (placeholder-handle-p "u-DEADBEEF")) ; uppercase hex (we use lowercase)
    (ng (placeholder-handle-p "u-1a2b3c4z")) ; non-hex char
    (ng (placeholder-handle-p nil))
    (ng (placeholder-handle-p ""))))

;;; --- GET /onboarding/handle ----------------------------------------------

(deftest onboarding-page-redirects-anonymous
  (testing "GET /onboarding/handle without session goes to /login"
    (with-mock-session (make-session)
      (let ((res (onboarding-handle-page-handler nil)))
        (ok (= 302 (response-status res)))
        (ok (string= "/login" (response-location res)))))))

(deftest onboarding-page-redirects-real-handle
  (testing "GET /onboarding/handle with a real handle redirects to /"
    (with-mock-session (make-session
                        :user '(:id "u123"
                                :email "alice@example.com"
                                :handle "alice"
                                :name "Alice"))
      (let ((res (onboarding-handle-page-handler nil)))
        (ok (= 302 (response-status res)))
        (ok (string= "/" (response-location res)))))))

(deftest onboarding-page-renders-for-placeholder-user
  (testing "GET /onboarding/handle shows the form when handle is a placeholder"
    (with-mock-session (make-session
                        :user '(:id "u123"
                                :email "alice@example.com"
                                :handle "u-12345678"
                                :name "Alice"))
      (let ((res (onboarding-handle-page-handler nil)))
        (ok (= 200 (response-status res)))
        (let ((body (first (response-body res))))
          (ok (search "/onboarding/handle" body)
              "form action should reference /onboarding/handle")
          (ok (search "u-12345678" body)
              "current placeholder should be shown as a hint and pre-fill")
          (ok (or (search "name=\"handle\"" body)
                  (search "name=handle" body))
              "form should include the handle input"))))))

;;; --- POST /onboarding/handle ---------------------------------------------

(deftest onboarding-create-redirects-anonymous
  (testing "POST /onboarding/handle without session goes to /login"
    (with-mock-session (make-session)
      (let ((res (onboarding-handle-create-handler '(("handle" . "alice")))))
        (ok (= 302 (response-status res)))
        (ok (string= "/login" (response-location res)))))))

(deftest onboarding-create-rejects-invalid-format
  (testing "POST /onboarding/handle rejects malformed handles"
    (with-test-db
      (let* ((dao (create-test-user :handle "u-deadbeef"))
             (user (mk-user-plist dao)))
        (with-mock-session (make-session :user user)
          ;; Too short.
          (let ((res (onboarding-handle-create-handler '(("handle" . "ab")))))
            (ok (= 400 (response-status res))
                "handle of length 2 must be rejected")
            (ok (search "Invalid handle" (first (response-body res)))
                "error message must mention invalid"))
          ;; DB unchanged.
          (let ((fresh (get-user-by-id (getf user :id))))
            (ok (string= "u-deadbeef" (users-handle fresh))
                "handle must NOT be saved when invalid"))
          ;; Trailing hyphen (matches HTML5 pattern but not server-side).
          (let ((res (onboarding-handle-create-handler '(("handle" . "alice-")))))
            (ok (= 400 (response-status res))
                "trailing-hyphen handle must be rejected"))
          ;; Uppercase letters (server normalises to lowercase, but we validate
          ;; the post-trim form; here we feed something with a space that
          ;; doesn't normalise into valid).
          (let ((res (onboarding-handle-create-handler '(("handle" . "  ")))))
            (ok (= 400 (response-status res))
                "blank handle must be rejected")))))))

(deftest onboarding-create-rejects-reserved
  (testing "POST /onboarding/handle rejects reserved words"
    (with-test-db
      (let* ((dao (create-test-user :handle "u-deadbeef"))
             (user (mk-user-plist dao)))
        (with-mock-session (make-session :user user)
          (let ((res (onboarding-handle-create-handler
                      '(("handle" . "admin")))))
            (ok (= 400 (response-status res))
                "reserved word must be rejected")
            (ok (search "reserved" (first (response-body res)))
                "error must mention reserved"))
          ;; DB unchanged.
          (let ((fresh (get-user-by-id (getf user :id))))
            (ok (string= "u-deadbeef" (users-handle fresh))
                "reserved handle must NOT be saved")))))))

(deftest onboarding-create-rejects-taken
  (testing "POST /onboarding/handle rejects an already-taken handle with 409"
    (with-test-db
      (let* ((existing (create-test-user :email-prefix "taken"
                                         :handle "alice"))
             (dao (create-test-user :email-prefix "newbie"
                                    :handle "u-deadbeef"))
             (user (mk-user-plist dao)))
        (declare (ignore existing))
        (with-mock-session (make-session :user user)
          (let ((res (onboarding-handle-create-handler
                      '(("handle" . "alice")))))
            (ok (= 409 (response-status res))
                "duplicate handle must return 409")
            (ok (search "already taken" (first (response-body res)))
                "error must mention already taken"))
          ;; DB unchanged.
          (let ((fresh (get-user-by-id (getf user :id))))
            (ok (string= "u-deadbeef" (users-handle fresh))
                "taken handle must NOT be saved")))))))

(deftest onboarding-create-saves-valid-handle
  (testing "POST /onboarding/handle persists a valid handle and updates session"
    (with-test-db
      (let* ((dao (create-test-user :email-prefix "newbie"
                                    :handle "u-deadbeef"))
             (user (mk-user-plist dao)))
        (with-mock-session (make-session :user user)
          (let ((res (onboarding-handle-create-handler
                      '(("handle" . "alice")))))
            (ok (= 302 (response-status res)))
            (ok (string= "/" (response-location res))
                "successful save must redirect to /"))
          ;; DB updated.
          (let ((fresh (get-user-by-id (getf user :id))))
            (ok (string= "alice" (users-handle fresh))
                "handle must be saved to the database"))
          ;; Session refreshed.
          (let ((session-user (gethash :user ningle/context:*session*)))
            (ok (string= "alice" (getf session-user :handle))
                "session plist must include the new handle")
            (ng (placeholder-handle-p (getf session-user :handle))
                "session handle must no longer satisfy placeholder-p")))))))

(deftest onboarding-create-trims-and-lowercases-input
  (testing "POST /onboarding/handle normalises whitespace and case"
    (with-test-db
      (let* ((dao (create-test-user :email-prefix "newbie"
                                    :handle "u-deadbeef"))
             (user (mk-user-plist dao)))
        (with-mock-session (make-session :user user)
          (let ((res (onboarding-handle-create-handler
                      '(("handle" . "  Bob-The-Builder  ")))))
            (ok (= 302 (response-status res))
                "trimmed/lowercased valid handle must be accepted"))
          (let ((fresh (get-user-by-id (getf user :id))))
            (ok (string= "bob-the-builder" (users-handle fresh))
                "saved handle must be lowercased and trimmed")))))))

;;; --- Middleware: require-real-handle --------------------------------------

(defun mk-env (&key path-info session)
  "Build a minimal Lack ENV plist for middleware tests."
  (list :path-info (or path-info "/dashboard/notebooks")
        :request-method :get
        :lack.session session))

(defun pass-through-app ()
  "App that always returns 200 with body 'OK'. Used to verify that
the middleware passes the request through."
  (lambda (env)
    (declare (ignore env))
    (list 200 (list :content-type "text/plain") (list "OK"))))

(deftest middleware-passes-anonymous-requests
  (testing "no session user => middleware does not redirect"
    (let ((wrapped (require-real-handle (pass-through-app)))
          (env (mk-env :path-info "/dashboard/notebooks" :session (make-hash-table))))
      (let ((res (funcall wrapped env)))
        (ok (= 200 (response-status res))
            "anonymous user should be passed through, not redirected")))))

(deftest middleware-passes-real-handle-on-protected-path
  (testing "user with real handle reaches protected page normally"
    (let ((session (make-hash-table)))
      (setf (gethash :user session)
            '(:id "u1" :handle "alice"))
      (let* ((wrapped (require-real-handle (pass-through-app)))
             (env (mk-env :path-info "/dashboard/notebooks" :session session))
             (res (funcall wrapped env)))
        (ok (= 200 (response-status res))
            "real-handle user should reach /dashboard/notebooks without redirect")))))

(deftest middleware-redirects-placeholder-on-protected-path
  (testing "placeholder user hitting /dashboard/notebooks is redirected"
    (let ((session (make-hash-table)))
      (setf (gethash :user session)
            '(:id "u1" :handle "u-deadbeef"))
      (let* ((wrapped (require-real-handle (pass-through-app)))
             (env (mk-env :path-info "/dashboard/notebooks" :session session))
             (res (funcall wrapped env)))
        (ok (= 302 (response-status res)))
        (ok (string= "/onboarding/handle" (response-location res))
            "placeholder users must be sent to /onboarding/handle")))))

(deftest middleware-allows-onboarding-page-for-placeholder
  (testing "placeholder user hitting /onboarding/handle is NOT redirected"
    (let ((session (make-hash-table)))
      (setf (gethash :user session)
            '(:id "u1" :handle "u-deadbeef"))
      (let* ((wrapped (require-real-handle (pass-through-app)))
             (env (mk-env :path-info "/onboarding/handle" :session session))
             (res (funcall wrapped env)))
        (ok (= 200 (response-status res))
            "the onboarding page itself must be reachable")))))

(deftest middleware-allows-public-paths-for-placeholder
  (testing "placeholder user can browse public surface"
    (let ((session (make-hash-table)))
      (setf (gethash :user session)
            '(:id "u1" :handle "u-deadbeef"))
      (let ((wrapped (require-real-handle (pass-through-app))))
        ;; / must be allowed.
        (let ((res (funcall wrapped (mk-env :path-info "/" :session session))))
          (ok (= 200 (response-status res)) "/ should be allowed"))
        ;; /notebooks (public listing) must be allowed.
        (let ((res (funcall wrapped (mk-env :path-info "/notebooks" :session session))))
          (ok (= 200 (response-status res)) "/notebooks should be allowed"))
        ;; /@<handle>/<slug> public notebook page must be allowed.
        (let ((res (funcall wrapped (mk-env :path-info "/@alice/some-slug" :session session))))
          (ok (= 200 (response-status res)) "/@<handle>/<slug> should be allowed"))
        ;; /c/@<handle>/<slug> public course page must be allowed.
        (let ((res (funcall wrapped (mk-env :path-info "/c/@alice/some-slug" :session session))))
          (ok (= 200 (response-status res)) "/c/@<handle>/<slug> should be allowed"))
        ;; /static/* must be allowed.
        (let ((res (funcall wrapped (mk-env :path-info "/static/app.css" :session session))))
          (ok (= 200 (response-status res)) "/static/* should be allowed"))
        ;; /auth/* must be allowed (login flow).
        (let ((res (funcall wrapped (mk-env :path-info "/auth/google/start" :session session))))
          (ok (= 200 (response-status res)) "/auth/* should be allowed"))
        ;; /login and /logout must be allowed.
        (let ((res (funcall wrapped (mk-env :path-info "/login" :session session))))
          (ok (= 200 (response-status res)) "/login should be allowed"))
        (let ((res (funcall wrapped (mk-env :path-info "/logout" :session session))))
          (ok (= 200 (response-status res)) "/logout should be allowed"))))))
