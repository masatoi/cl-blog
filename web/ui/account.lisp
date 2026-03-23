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

(defparameter *delete-modal-script*
  "document.addEventListener('DOMContentLoaded',function(){var modal=document.getElementById('account-delete-modal');if(!modal){return;}var messageEl=modal.querySelector('[data-role=\"message\"]');var confirmBtn=modal.querySelector('[data-role=\"confirm\"]');var cancelBtn=modal.querySelector('[data-role=\"cancel\"]');var activeForm=null;var openModal=function(form){activeForm=form;var email=form.getAttribute('data-email')||'your account';messageEl.textContent='Deleting '+email+' will remove all datasets, features, jobs, and stored files.';modal.setAttribute('data-open','true');confirmBtn.focus();};var closeModal=function(){modal.setAttribute('data-open','false');activeForm=null;};document.querySelectorAll('form[data-role=\"account-delete\"]').forEach(function(form){form.addEventListener('submit',function(evt){if(modal.getAttribute('data-open')==='true'){return;}evt.preventDefault();openModal(form);});});confirmBtn.addEventListener('click',function(){if(activeForm){var form=activeForm;closeModal();form.submit();}});cancelBtn.addEventListener('click',function(){closeModal();});modal.addEventListener('click',function(evt){if(evt.target===modal){closeModal();}});document.addEventListener('keydown',function(evt){if(evt.key==='Escape'&&modal.getAttribute('data-open')==='true'){evt.preventDefault();closeModal();}});});")

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
              (:form :method "post"
                     :action "/account/delete"
                     :data-role "account-delete"
                     :data-email email
                (:button :type "submit" :class "button-danger" "Delete account"))))
          ;; Delete confirmation modal
          (:div :id "account-delete-modal"
                :class "modal-overlay"
                :data-open "false"
                :role "dialog"
                :aria-modal "true"
                :aria-labelledby "account-delete-title"
            (:div :class "modal-card"
              (:h3 :id "account-delete-title" "Delete your account?")
              (:p :data-role "message" "Deleting your account removes all datasets, features, jobs, and stored files associated with it.")
              (:div :class "modal-actions"
                (:button :type "button" :class "button-secondary" :data-role "cancel" "Keep account")
                (:button :type "button" :class "button-danger" :data-role "confirm" "Delete account"))))
          (:script (:raw *delete-modal-script*)))))))
