;;;; web/ui/signup.lisp --- User registration page.

(defpackage #:cl-blog/web/ui/signup
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:cl-blog/web/ui/styles
                #:auth-page-styles)
  (:export #:render))

(in-package #:cl-blog/web/ui/signup)

(defun render (&key error)
  "Render the signup page as an HTML string."
  (spinneret:with-html-string
    (:doctype)
    (:html
      (:head
        (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title "cl-blog - Sign up")
        (:style (:raw (auth-page-styles))))
      (:body
        (:div :class "auth-container"
          (:div :class "app-name" "Create a new account")
          (when error
            (:div :class "error" error))
          (:h1 "Get started")
          (:form :method "post" :action "/signup"
            (:label :for "name" "Display name")
            (:input :type "text" :id "name" :name "name" :required t :autocomplete "name")
            (:label :for "email" "Email")
            (:input :type "email" :id "email" :name "email" :required t :autocomplete "email")
            (:label :for "password" "Password")
            (:input :type "password" :id "password" :name "password" :required t :autocomplete "new-password")
            (:button :type "submit" :class "button-primary" "Create account"))
          (:p :class "app-name"
            "Already have an account? "
            (:a :href "/login" "Sign in")))))))
