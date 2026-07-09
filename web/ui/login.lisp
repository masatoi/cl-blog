;;;; web/ui/login.lisp --- Login page.

(defpackage #:recurya/web/ui/login
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/styles
                #:auth-page-styles)
  (:import-from #:recurya/web/oauth
                #:dev-stub-enabled-p
                #:dev-stub-email)
  (:import-from #:recurya/web/i18n/core
                #:tr)
  (:export #:render))

(in-package #:recurya/web/ui/login)

(defun render (&key error)
  "Render the OAuth login page with provider sign-in buttons."
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head
      (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:title (tr :login.page_title))
      (:style (:raw (auth-page-styles))))
     (:body
      (:div :class "auth-container"
            (:div :class "app-name" (tr :login.heading))
            (when error
              (:div :class "error" error))
            (when (dev-stub-enabled-p)
              (:div :class "dev-banner"
                    (:strong (tr :login.dev_stub.title))
                    (tr :login.dev_stub.reuse_prefix)
                    (:code (dev-stub-email))
                    (tr :login.dev_stub.reuse_suffix)))
            (:h1 (tr :login.welcome))
            (:p :class "auth-help"
                (tr :login.help))
            (:a :class "button-primary oauth-button oauth-google"
                :href "/auth/google/start"
                (tr :login.button.google))
            (:a :class "button-primary oauth-button oauth-github"
                :href "/auth/github/start"
                (tr :login.button.github))
            (:p :class "app-name auth-footnote"
                (tr :login.footnote)))))))
