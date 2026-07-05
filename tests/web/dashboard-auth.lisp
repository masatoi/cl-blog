;;;; tests/web/dashboard-auth.lisp --- Tests for the require-dashboard-auth
;;;; Lack middleware.
;;;;
;;;; Covers:
;;;;   * Anonymous requests to /dashboard and /dashboard/* are redirected
;;;;     to /login.
;;;;   * Public paths (e.g. /notebooks, /, /login) are NOT redirected.
;;;;   * Authenticated requests pass through to the wrapped app.
;;;;   * Composition with require-real-handle: an authenticated user with a
;;;;     placeholder handle hits the login gate (pass through), then is
;;;;     redirected to /onboarding/handle by the next middleware in the chain.

(defpackage #:recurya/tests/web/dashboard-auth
  (:use #:cl
        #:rove)
  (:import-from #:recurya/web/auth
                #:require-dashboard-auth
                #:require-real-handle))

(in-package #:recurya/tests/web/dashboard-auth)

;;; --- Helpers --------------------------------------------------------------

(defun mk-env (&key path-info session (request-method :get))
  "Build a minimal Lack ENV plist for middleware tests."
  (list :path-info (or path-info "/dashboard")
        :request-method request-method
        :lack.session session))

(defun pass-through-app ()
  "App that always returns 200 with body 'OK'. Used to verify that
the middleware passes the request through."
  (lambda (env)
    (declare (ignore env))
    (list 200 (list :content-type "text/plain") (list "OK"))))

(defun make-session (&key user)
  "Create a session hash table optionally seeded with USER under :user."
  (let ((ht (make-hash-table)))
    (when user
      (setf (gethash :user ht) user))
    ht))

(defun response-status (response) (first response))
(defun response-headers (response) (second response))
(defun response-location (response)
  (getf (response-headers response) :location))

;;; --- Anonymous redirects --------------------------------------------------

(deftest dashboard-auth-redirects-anonymous-on-dashboard-root
  (testing "anonymous GET /dashboard -> 302 /login"
    (let* ((wrapped (require-dashboard-auth (pass-through-app)))
           (env (mk-env :path-info "/dashboard"
                        :session (make-session)))
           (res (funcall wrapped env)))
      (ok (= 302 (response-status res))
          "anonymous user on /dashboard must be redirected")
      (ok (string= "/login" (response-location res))
          "redirect target must be /login"))))

(deftest dashboard-auth-redirects-anonymous-on-subpath
  (testing "anonymous GET /dashboard/notebooks -> 302 /login"
    (let* ((wrapped (require-dashboard-auth (pass-through-app)))
           (env (mk-env :path-info "/dashboard/notebooks"
                        :session (make-session)))
           (res (funcall wrapped env)))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest dashboard-auth-redirects-anonymous-on-post
  (testing "anonymous POST /dashboard/notebooks -> 302 /login"
    (let* ((wrapped (require-dashboard-auth (pass-through-app)))
           (env (mk-env :path-info "/dashboard/notebooks"
                        :request-method :post
                        :session (make-session)))
           (res (funcall wrapped env)))
      (ok (= 302 (response-status res))
          "POST gating must apply too, not just GET")
      (ok (string= "/login" (response-location res))))))

(deftest dashboard-auth-redirects-anonymous-with-no-session-key
  (testing "no :lack.session at all -> still redirects on dashboard path"
    (let* ((wrapped (require-dashboard-auth (pass-through-app)))
           (env (list :path-info "/dashboard/courses"
                      :request-method :get))
           (res (funcall wrapped env)))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

;;; --- Public paths must not be over-fired ---------------------------------

(deftest dashboard-auth-does-not-redirect-public-paths
  (testing "anonymous GET /notebooks (public) is NOT redirected"
    (let ((wrapped (require-dashboard-auth (pass-through-app))))
      (dolist (p '("/" "/login" "/notebooks" "/courses"
                   "/@alice/some-slug" "/c/@alice/some-slug"
                   "/auth/google/start" "/static/app.css"
                   "/onboarding/handle"
                   ;; Adversarial: paths that merely START with the
                   ;; substring "dashboard" but are NOT under /dashboard.
                   "/dashboards" "/dashboardia"))
        (let ((res (funcall wrapped
                            (mk-env :path-info p
                                    :session (make-session)))))
          (ok (= 200 (response-status res))
              (format nil "~A must pass through (not be redirected)" p)))))))

;;; --- Authenticated users pass through ------------------------------------

(deftest dashboard-auth-passes-authenticated-on-dashboard
  (testing "authenticated GET /dashboard -> reaches wrapped app (no /login redirect)"
    (let* ((session (make-session :user '(:id "u1" :handle "alice")))
           (wrapped (require-dashboard-auth (pass-through-app)))
           (env (mk-env :path-info "/dashboard" :session session))
           (res (funcall wrapped env)))
      (ok (= 200 (response-status res))
          "authenticated user must reach the wrapped app, not get 302 /login"))))

(deftest dashboard-auth-passes-authenticated-on-subpath
  (testing "authenticated GET /dashboard/notebooks -> reaches wrapped app"
    (let* ((session (make-session :user '(:id "u1" :handle "alice")))
           (wrapped (require-dashboard-auth (pass-through-app)))
           (env (mk-env :path-info "/dashboard/notebooks" :session session))
           (res (funcall wrapped env)))
      (ok (= 200 (response-status res))))))

;;; --- Composition with require-real-handle --------------------------------

(deftest dashboard-auth-composes-with-real-handle-placeholder
  (testing "auth'd user with placeholder handle hitting /dashboard is sent to /onboarding/handle"
    ;; Order matches build-app: dashboard-auth wraps real-handle wraps app.
    ;; A logged-in user with a placeholder handle should pass the login gate
    ;; and then be intercepted by require-real-handle.
    (let* ((session (make-session :user '(:id "u1" :handle "u-deadbeef")))
           (chain (require-dashboard-auth
                   (require-real-handle (pass-through-app))))
           (env (mk-env :path-info "/dashboard" :session session))
           (res (funcall chain env)))
      (ok (= 302 (response-status res))
          "placeholder user must be redirected, not pass through")
      (ok (string= "/onboarding/handle" (response-location res))
          "redirect target must be /onboarding/handle (not /login)"))))

(deftest dashboard-auth-composes-with-real-handle-real
  (testing "auth'd user with real handle hitting /dashboard -> reaches app"
    (let* ((session (make-session :user '(:id "u1" :handle "alice")))
           (chain (require-dashboard-auth
                   (require-real-handle (pass-through-app))))
           (env (mk-env :path-info "/dashboard/notebooks"
                        :session session))
           (res (funcall chain env)))
      (ok (= 200 (response-status res))
          "real-handle user must reach the wrapped app on /dashboard/*"))))

(deftest dashboard-auth-composes-anonymous-prefers-login
  (testing "anonymous /dashboard hits /login (not /onboarding/handle)"
    ;; Confirms the middleware ordering: the login gate fires first, so a
    ;; logged-out visitor never gets sent to onboarding by mistake.
    (let* ((chain (require-dashboard-auth
                   (require-real-handle (pass-through-app))))
           (env (mk-env :path-info "/dashboard"
                        :session (make-session)))
           (res (funcall chain env)))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))
          "anonymous users must be sent to /login, not /onboarding/handle"))))
