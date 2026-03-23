(defpackage #:cl-blog/web/ui/login
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:cl-blog/web/ui/styles
                #:auth-page-styles)
  (:export #:render))

(in-package #:cl-blog/web/ui/login)


(defun render (&key error)
  "Render the login page as an HTML string."
  (spinneret:with-html-string
    (:doctype)
    (:html
      (:head
        (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title "cl-blog - Sign in")
        (:style (:raw (auth-page-styles))))
      (:body
        (:div :class "auth-container"
          (:div :class "app-name" "Sign in to continue to cl-blog")
          (when error
            (:div :class "error" error))
          (:h1 "Welcome back")
          (:form :method "post" :action "/login"
            (:label :for "email" "Email")
            (:input :type "email" :id "email" :name "email" :required t :autocomplete "email")
            (:label :for "password" "Password")
            (:input :type "password" :id "password" :name "password" :required t :autocomplete "current-password")
            (:button :type "submit" :class "button-primary" "Sign in"))
          (:p :class "app-name" "Demo credentials: admin@cl-blog.dev / changeme")
          (:p :class "app-name"
            "Need an account? "
            (:a :href "/signup" "Sign up")))))))
