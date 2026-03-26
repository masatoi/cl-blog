;;;; web/ui/errors.lisp --- Error pages (404, 500).

(defpackage #:recurya/web/ui/errors
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/styles
                #:*color-vars*
                #:*base-styles*)
  (:export #:not-found
           #:server-error))

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
        (:title "404 - Not Found")
        (:style (:raw (error-styles))))
      (:body
        (:div :class "error-container"
          (:h1 "404")
          (:p "The page you're looking for doesn't exist.")
          (:a :href "/dashboard" "Go to Dashboard"))))))

(defun server-error (&key message)
  "Render a 500 Server Error page."
  (spinneret:with-html-string
    (:doctype)
    (:html
      (:head
        (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title "500 - Server Error")
        (:style (:raw (error-styles))))
      (:body
        (:div :class "error-container"
          (:h1 "500")
          (:p (or message "Something went wrong on our end."))
          (:a :href "/dashboard" "Go to Dashboard"))))))
