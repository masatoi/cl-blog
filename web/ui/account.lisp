;;;; web/ui/account.lisp --- Account settings page with HTMX delete modal.
;;;;
;;;; Renders profile settings (display name, language, timezone) and a
;;;; danger zone with HTMX-powered account deletion confirmation modal.

(defpackage #:recurya/web/ui/account
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/layout
                #:common-styles
                #:page-shell)
  (:import-from #:recurya/web/ui/csrf
                #:csrf-input)
  (:import-from #:recurya/web/i18n/core
                #:tr
                #:available-locales)
  (:export #:render))

(in-package #:recurya/web/ui/account)

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
        (page-styles (concatenate 'string (common-styles) *account-styles*)))
    (page-shell
     :title (tr :account.page_title)
     :styles page-styles
     :user user
     :body-content
     (with-html-string
       (:div :class "card"
         (:h1 (tr :account.heading))
         (:p :class "muted" (tr :account.subtitle))
         (when message
           (:div :class "message success" message))
         (when error
           (:div :class "message error" error))
         (:form :class "settings" :method "post" :action "/account"
           (:raw (csrf-input))
           (:div
             (:label :for "account-email" (tr :account.field.email))
             (:input :id "account-email" :type "text" :value email :readonly t))
           (:div
             (:label :for "account-display-name" (tr :account.field.display_name))
             (:input :id "account-display-name"
                     :name "display-name"
                     :type "text"
                     :value display-name
                     :required t
                     :minlength "1"
                     :maxlength "120"))
           ;; Language and Timezone settings
           (:div :class "settings-section"
             (:h3 (tr :account.regional.heading))
             (:div :class "settings-row"
               (:div
                 (:label :for "account-language" (tr :account.regional.language))
                 (:select :id "account-language" :name "language"
                   (dolist (lang *languages*)
                     (let ((code (car lang))
                           (label (cdr lang)))
                       (when (member code (available-locales)
                                     :key #'symbol-name :test #'string-equal)
                         (if (string= code language)
                             (:option :value code :selected t label)
                             (:option :value code label)))))))
               (:div
                 (:label :for "account-timezone" (tr :account.regional.timezone))
                 (:select :id "account-timezone" :name "timezone"
                   (dolist (tz *timezones*)
                     (let ((code (car tz))
                           (label (cdr tz)))
                       (if (string= code timezone)
                           (:option :value code :selected t label)
                           (:option :value code label))))))))
           (:button :type "submit" :class "button-primary" (tr :account.save))))
       (:div :class "card"
         (:h2 (tr :account.danger.heading))
         (:p :class "muted" (tr :account.danger.body))
         (:button :type "button" :class "button-danger"
                  :hx-get "/account/confirm-delete"
                  :hx-target "#modal-container"
                  :hx-swap "innerHTML"
                  (tr :account.danger.delete)))
       (:div :id "modal-container")))))
