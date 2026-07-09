;;;; web/ui/errors.lisp --- Error pages (404, 500).

(defpackage #:recurya/web/ui/errors
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/styles
                #:*color-vars*
                #:*base-styles*)
  (:import-from #:recurya/web/i18n/core
                #:tr)
  (:export #:not-found
           #:server-error
           #:csrf-failure))

(in-package #:recurya/web/ui/errors)

(defparameter *error-page-styles*
  ".error-container {
  max-width: 600px;
  margin: 10rem auto;
  text-align: center;
  padding: 2rem;
  color: var(--color-text-light);
}

.error-container h1 {
  font-size: 4rem;
  margin: 0;
  color: var(--color-error);
}

.error-container p {
  font-size: 1.2rem;
  color: var(--color-text-faint);
}")

(defun error-styles ()
  "Return styles for error pages."
  (concatenate 'string *color-vars* *base-styles* *error-page-styles*))

(defun not-found ()
  "Render a 404 Not Found page."
  (spinneret:with-html-string
    (:doctype)
    (:html
      (:head
        (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title (tr :errors.not_found.title))
        (:style (:raw (error-styles))))
      (:body
        (:div :class "error-container"
          (:h1 "404")
          (:p (tr :errors.not_found.body))
          (:a :href "/dashboard" (tr :errors.actions.go_to_dashboard)))))))

(defun server-error (&key message)
  "Render a 500 Server Error page."
  (spinneret:with-html-string
    (:doctype)
    (:html
      (:head
        (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title (tr :errors.server_error.title))
        (:style (:raw (error-styles))))
      (:body
        (:div :class "error-container"
          (:h1 "500")
          (:p (or message (tr :errors.server_error.body)))
          (:a :href "/dashboard" (tr :errors.actions.go_to_dashboard)))))))

(defun csrf-failure ()
  "Render a 400 page returned when a state-changing request arrives
without a valid CSRF token (typically because the form was submitted
from a stale tab or a cross-origin attacker page)."
  (spinneret:with-html-string
    (:doctype)
    (:html
      (:head
        (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title (tr :errors.csrf.title))
        (:style (:raw (error-styles))))
      (:body
        (:div :class "error-container"
          (:h1 "400")
          (:p (tr :errors.csrf.body))
          (:a :href "/" (tr :errors.actions.home)))))))
