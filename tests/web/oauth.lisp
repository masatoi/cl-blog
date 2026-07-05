;;;; tests/web/oauth.lisp --- Tests for OAuth provider library.

(defpackage #:recurya/tests/web/oauth
  (:use #:cl
        #:rove)
  (:import-from #:recurya/web/oauth
                #:generate-state
                #:find-provider
                #:provider-configured-p
                #:build-authorize-url
                #:redirect-uri
                #:exchange-code
                #:fetch-userinfo
                #:extract-email
                #:extract-uid
                #:extract-name
                #:oauth-provider-name
                #:*http-post-fn*
                #:*http-get-fn*))

(in-package #:recurya/tests/web/oauth)

(defun call-with-env (bindings thunk)
  (let ((saved (loop for (k . v) in bindings
                     collect (cons k (uiop:getenv k)))))
    (unwind-protect
         (progn
           (loop for (k . v) in bindings
                 do (setf (uiop:getenv k) (or v "")))
           (funcall thunk))
      (loop for (k . v) in saved
            do (setf (uiop:getenv k) (or v ""))))))

(defmacro with-env ((&rest bindings) &body body)
  `(call-with-env (list ,@(loop for (k v) on bindings by #'cddr
                                collect `(cons ,k ,v)))
                  (lambda () ,@body)))

(deftest oauth-state-generation
  (testing "generate-state produces a 32-character hex string"
    (let ((state (generate-state)))
      (ok (stringp state))
      (ok (= 32 (length state)))
      (ok (every (lambda (c)
                   (or (digit-char-p c)
                       (find c "abcdef" :test #'char=)))
                 state))))
  (testing "consecutive states differ"
    (ok (not (string= (generate-state) (generate-state))))))

(deftest oauth-find-provider
  (testing "google and github are registered"
    (let ((g (find-provider "google"))
          (gh (find-provider "github")))
      (ok g "google provider exists")
      (ok gh "github provider exists")
      (ok (string= "google" (oauth-provider-name g)))
      (ok (string= "github" (oauth-provider-name gh)))))
  (testing "lookup is case-insensitive"
    (ok (find-provider "Google"))
    (ok (find-provider "GITHUB")))
  (testing "unknown provider returns nil"
    (ok (null (find-provider "twitter")))))

(deftest oauth-provider-configured-p
  (testing "returns nil when env vars are blank"
    (with-env ("OAUTH_DEV_STUB" ""
               "OAUTH_GOOGLE_CLIENT_ID" ""
               "OAUTH_GOOGLE_CLIENT_SECRET" "")
      (ok (null (provider-configured-p (find-provider "google"))))))
  (testing "returns t when both id and secret are set"
    (with-env ("OAUTH_DEV_STUB" ""
               "OAUTH_GOOGLE_CLIENT_ID" "abc"
               "OAUTH_GOOGLE_CLIENT_SECRET" "xyz")
      (ok (provider-configured-p (find-provider "google"))))))

(deftest oauth-authorize-url-construction
  (testing "google authorize URL contains all required parameters"
    (with-env ("OAUTH_DEV_STUB" ""
               "OAUTH_GOOGLE_CLIENT_ID" "google-id-123"
               "OAUTH_GOOGLE_CLIENT_SECRET" "google-secret"
               "OAUTH_REDIRECT_BASE" "https://example.test")
      (let ((url (build-authorize-url (find-provider "google") "state-abc")))
        (ok (search "https://accounts.google.com/o/oauth2/v2/auth" url))
        (ok (search "client_id=google-id-123" url))
        (ok (search "state=state-abc" url))
        (ok (search "response_type=code" url))
        (ok (search "scope=openid" url))
        (ok (search "redirect_uri=https%3A%2F%2Fexample.test%2Fauth%2Fgoogle%2Fcallback" url)))))
  (testing "github authorize URL targets the github endpoint"
    (with-env ("OAUTH_DEV_STUB" ""
               "OAUTH_GITHUB_CLIENT_ID" "gh-id"
               "OAUTH_GITHUB_CLIENT_SECRET" "gh-secret"
               "OAUTH_REDIRECT_BASE" "https://example.test")
      (let ((url (build-authorize-url (find-provider "github") "s")))
        (ok (search "https://github.com/login/oauth/authorize" url))
        (ok (search "client_id=gh-id" url))
        (ok (search "scope=read%3Auser%20user%3Aemail" url))))))

(deftest oauth-redirect-uri
  (testing "redirect-uri uses OAUTH_REDIRECT_BASE"
    (with-env ("OAUTH_REDIRECT_BASE" "https://app.example.com")
      (ok (string= "https://app.example.com/auth/google/callback"
                   (redirect-uri (find-provider "google"))))
      (ok (string= "https://app.example.com/auth/github/callback"
                   (redirect-uri (find-provider "github"))))))
  (testing "falls back to localhost when env is unset"
    (with-env ("OAUTH_REDIRECT_BASE" "")
      (ok (search "http://localhost:13000/auth/google/callback"
                  (redirect-uri (find-provider "google")))))))

(deftest oauth-exchange-code-stubbed
  (testing "exchange-code parses access_token from token endpoint JSON"
    (with-env ("OAUTH_DEV_STUB" ""
               "OAUTH_GOOGLE_CLIENT_ID" "id"
               "OAUTH_GOOGLE_CLIENT_SECRET" "secret"
               "OAUTH_REDIRECT_BASE" "https://e.test")
      (let* ((captured-url nil)
             (captured-body nil)
             (*http-post-fn*
               (lambda (url &key content headers)
                 (declare (ignore headers))
                 (setf captured-url url)
                 (setf captured-body content)
                 "{\"access_token\":\"AT-123\",\"token_type\":\"Bearer\"}"))
             (token (exchange-code (find-provider "google") "code-xyz")))
        (ok (string= "AT-123" token))
        (ok (string= "https://oauth2.googleapis.com/token" captured-url))
        (ok (search "code=code-xyz" captured-body))
        (ok (search "client_id=id" captured-body))
        (ok (search "client_secret=secret" captured-body))
        (ok (search "grant_type=authorization_code" captured-body))))))

(deftest oauth-fetch-userinfo-stubbed
  (testing "fetch-userinfo returns parsed JSON hash-table"
    (with-env ("OAUTH_DEV_STUB" "")
      (let* ((captured-url nil)
             (captured-headers nil)
             (*http-get-fn*
               (lambda (url &key headers)
                 (setf captured-url url)
                 (setf captured-headers headers)
                 "{\"sub\":\"1234\",\"email\":\"u@example.com\",\"name\":\"User\"}"))
             (info (fetch-userinfo (find-provider "google") "AT-99")))
        (ok (hash-table-p info))
        (ok (string= "1234" (gethash "sub" info)))
        (ok (string= "u@example.com" (gethash "email" info)))
        (ok (string= "https://www.googleapis.com/oauth2/v3/userinfo" captured-url))
        (ok (search "Bearer AT-99"
                    (cdr (assoc "Authorization" captured-headers :test #'string=))))))))

(deftest oauth-extract-fields-google
  (testing "google extracts email/uid/name from userinfo"
    (let ((info (make-hash-table :test 'equal)))
      (setf (gethash "sub" info) "g-uid-1")
      (setf (gethash "email" info) "alice@example.com")
      (setf (gethash "name" info) "Alice")
      (let ((p (find-provider "google")))
        (ok (string= "alice@example.com" (extract-email p info "tok")))
        (ok (string= "g-uid-1" (extract-uid p info)))
        (ok (string= "Alice" (extract-name p info)))))))

(deftest oauth-extract-fields-github
  (testing "github stringifies numeric id and falls back to login for name"
    (let ((info (make-hash-table :test 'equal)))
      (setf (gethash "id" info) 99001)
      (setf (gethash "email" info) "bob@example.com")
      (setf (gethash "login" info) "bobby")
      (let ((p (find-provider "github")))
        (ok (string= "99001" (extract-uid p info)))
        (ok (string= "bobby" (extract-name p info)))
        (ok (string= "bob@example.com" (extract-email p info "tok"))))))
  (testing "github falls back to /user/emails when public email is null"
    (with-env ("OAUTH_DEV_STUB" "")
      (let ((info (make-hash-table :test 'equal))
            (*http-get-fn*
              (lambda (url &key headers)
                (declare (ignore headers))
                (cond
                  ((search "/user/emails" url)
                   "[{\"email\":\"primary@example.com\",\"primary\":true,\"verified\":true},{\"email\":\"alt@example.com\",\"primary\":false,\"verified\":true}]")
                  (t "{}")))))
        (setf (gethash "id" info) 1)
        (setf (gethash "email" info) nil)
        (setf (gethash "login" info) "x")
        (let ((p (find-provider "github")))
          (ok (string= "primary@example.com" (extract-email p info "tok"))))))))

(deftest oauth-dev-stub-gate
  (testing "dev stub is gated by both env vars"
    (with-env ("OAUTH_DEV_STUB" "" "OAUTH_REDIRECT_BASE" "http://localhost:3000")
      (ok (null (recurya/web/oauth:dev-stub-enabled-p))
          "off when OAUTH_DEV_STUB is empty"))
    (with-env ("OAUTH_DEV_STUB" "1" "OAUTH_REDIRECT_BASE" "http://localhost:3000")
      (ok (recurya/web/oauth:dev-stub-enabled-p)
          "on for localhost"))
    (with-env ("OAUTH_DEV_STUB" "1" "OAUTH_REDIRECT_BASE" "https://recurya.example.com")
      (ok (null (recurya/web/oauth:dev-stub-enabled-p))
          "off when redirect base is non-localhost (production guard)"))
    (with-env ("OAUTH_DEV_STUB" "1" "OAUTH_REDIRECT_BASE" "https://abc123.ngrok-free.app")
      (ok (recurya/web/oauth:dev-stub-enabled-p)
          "on for ngrok-free tunnels"))
    (with-env ("OAUTH_DEV_STUB" "1" "OAUTH_REDIRECT_BASE" "https://my-tunnel.ngrok.app")
      (ok (recurya/web/oauth:dev-stub-enabled-p)
          "on for paid ngrok tunnels"))))

(deftest oauth-dev-stub-authorize-url-redirects-locally
  (testing "build-authorize-url skips the provider in stub mode"
    (with-env ("OAUTH_DEV_STUB" "1" "OAUTH_REDIRECT_BASE" "http://localhost:3000")
      (let ((url (build-authorize-url (find-provider "google") "abc123")))
        (ok (search "/auth/google/callback" url)
            "callback URL is local")
        (ok (null (search "accounts.google.com" url))
            "does not redirect to Google")
        (ok (search "code=DEV-CODE" url) "uses DEV-CODE")
        (ok (search "state=abc123" url) "preserves state for CSRF check")))))

(deftest oauth-dev-stub-exchange-and-userinfo
  (testing "exchange-code and fetch-userinfo return dev data without HTTP"
    (with-env ("OAUTH_DEV_STUB" "1"
               "OAUTH_REDIRECT_BASE" "http://localhost:3000"
               "OAUTH_DEV_EMAIL" "alice@dev.local"
               "OAUTH_DEV_NAME" "Alice (Dev)")
      (let ((called nil))
        (let ((*http-post-fn*
                (lambda (&rest a) (declare (ignore a)) (setf called t) "{}"))
              (*http-get-fn*
                (lambda (&rest a) (declare (ignore a)) (setf called t) "{}")))
          (let* ((token (exchange-code (find-provider "google") "ignored-code"))
                 (info (fetch-userinfo (find-provider "google") token)))
            (ok (string= "DEV-ACCESS-TOKEN" token))
            (ok (hash-table-p info))
            (ok (string= "alice@dev.local" (gethash "email" info)))
            (ok (string= "Alice (Dev)" (gethash "name" info)))
            (ok (string= "dev-google" (gethash "sub" info)))
            (ok (null called) "no real HTTP call was issued")))))))

(deftest oauth-dev-stub-bypasses-provider-configured-check
  (testing "provider-configured-p returns t in stub mode without env client id/secret"
    (with-env ("OAUTH_DEV_STUB" "1"
               "OAUTH_REDIRECT_BASE" "http://localhost:3000"
               "OAUTH_GOOGLE_CLIENT_ID" ""
               "OAUTH_GOOGLE_CLIENT_SECRET" "")
      (ok (provider-configured-p (find-provider "google"))))
    (testing "with stub off, returns nil when env is missing"
      (with-env ("OAUTH_DEV_STUB" ""
                 "OAUTH_REDIRECT_BASE" "http://localhost:3000"
                 "OAUTH_GOOGLE_CLIENT_ID" ""
                 "OAUTH_GOOGLE_CLIENT_SECRET" "")
        (ok (null (provider-configured-p (find-provider "google"))))))))
