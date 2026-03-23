;;;; web/ui/account.lisp --- Account settings page with HTMX delete modal.
;;;;
;;;; Renders profile settings (display name, language, timezone) and a
;;;; danger zone with HTMX-powered account deletion confirmation modal.

(defpackage #:cl-blog/web/ui/account
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:cl-blog/web/ui/layout
                #:header
                #:header-styles
                #:common-styles)
  (:export #:render))

(in-package #:cl-blog/web/ui/account)

(defparameter *account-styles*
  "/* Account page specific styles */
form.settings {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  margin-top: 1.5rem;
}

form.settings .button-primary {
  align-self: flex-start;
}

.settings-section {
  margin-top: 1.5rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--color-border-light);
}

.settings-section h3 {
  margin: 0 0 1rem 0;
  font-size: 1rem;
  color: var(--color-text-dark);
}

.settings-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
}

@media (max-width: 640px) {
  .settings-row {
    grid-template-columns: 1fr;
  }
}")

(defparameter *languages*
  '(("en" . "English")
    ("ja" . "日本語")
    ("zh" . "中文")
    ("ko" . "한국어")
    ("es" . "Español")
    ("fr" . "Français")
    ("de" . "Deutsch")
    ("pt" . "Português")
    ("it" . "Italiano"))
  "Supported language options for user preferences.")

(defparameter *timezones*
  '(("UTC" . "UTC")
    ("America/New_York" . "Eastern Time (US)")
    ("America/Chicago" . "Central Time (US)")
    ("America/Denver" . "Mountain Time (US)")
    ("America/Los_Angeles" . "Pacific Time (US)")
    ("Europe/London" . "London")
    ("Europe/Paris" . "Paris / Berlin")
    ("Europe/Moscow" . "Moscow")
    ("Asia/Dubai" . "Dubai")
    ("Asia/Kolkata" . "India")
    ("Asia/Singapore" . "Singapore")
    ("Asia/Shanghai" . "China")
    ("Asia/Tokyo" . "Tokyo")
    ("Asia/Seoul" . "Seoul")
    ("Australia/Sydney" . "Sydney")
    ("Pacific/Auckland" . "Auckland"))
  "Common timezone options for user preferences.")

(defun render (&key user message error)
  "Render the account settings page."
  (let ((email (getf user :email))
        (display-name (or (getf user :name) ""))
        (language (or (getf user :language) "en"))
        (timezone (or (getf user :timezone) "UTC"))
        (all-styles (concatenate 'string (common-styles) (header-styles) *account-styles*)))
    (spinneret:with-html-string
      (:doctype)
      (:html
        (:head
          (:meta :charset "utf-8")
          (:meta :name "viewport" :content "width=device-width, initial-scale=1")
          (:title "Account settings - cl-blog")
          (:script :src "https://unpkg.com/htmx.org@2.0.4"
           :integrity "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
           :crossorigin "anonymous")
          (:style (:raw all-styles)))
        (:body
          (:raw (header user))
          (:main
            (:div :class "card"
              (:h1 "Account settings")
              (:p :class "muted" "Update your profile information or request account deletion.")
              (when message
                (:div :class "message success" message))
              (when error
                (:div :class "message error" error))
              (:form :class "settings" :method "post" :action "/account"
                (:div
                  (:label :for "account-email" "Email")
                  (:input :id "account-email" :type "text" :value email :readonly t))
                (:div
                  (:label :for "account-display-name" "Display name")
                  (:input :id "account-display-name"
                          :name "display-name"
                          :type "text"
                          :value display-name
                          :required t
                          :minlength "1"
                          :maxlength "120"))
                ;; Language and Timezone settings
                (:div :class "settings-section"
                  (:h3 "Regional settings")
                  (:div :class "settings-row"
                    (:div
                      (:label :for "account-language" "Language")
                      (:select :id "account-language" :name "language"
                        (dolist (lang *languages*)
                          (let ((code (car lang))
                                (label (cdr lang)))
                            (if (string= code language)
                                (:option :value code :selected t label)
                                (:option :value code label))))))
                    (:div
                      (:label :for "account-timezone" "Timezone")
                      (:select :id "account-timezone" :name "timezone"
                        (dolist (tz *timezones*)
                          (let ((code (car tz))
                                (label (cdr tz)))
                            (if (string= code timezone)
                                (:option :value code :selected t label)
                                (:option :value code label))))))))
                (:button :type "submit" :class "button-primary" "Save changes")))
            (:div :class "card"
              (:h2 "Danger zone")
              (:p :class "muted" "Deleting your account removes all datasets, features, jobs, and stored files. This action cannot be undone.")
              (:button :type "button" :class "button-danger"
                       :hx-get "/account/confirm-delete"
                       :hx-target "#modal-container"
                       :hx-swap "innerHTML"
                       "Delete account")))
          (:div :id "modal-container"))))))
