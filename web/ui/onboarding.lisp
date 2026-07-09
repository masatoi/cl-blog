;;;; web/ui/onboarding.lisp --- Onboarding handle setup page.
;;;;
;;;; Renders the form a newly-signed-up OAuth user fills out to pick a
;;;; permanent handle. After Phase 5 every fresh OAuth account starts
;;;; with a placeholder handle of the form 'u-<8 hex>'; the
;;;; corresponding routes (web/routes.lisp) and the require-real-handle
;;;; middleware (web/auth.lisp) push such users here until they choose
;;;; a real handle.

(defpackage #:recurya/web/ui/onboarding
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/styles
                #:auth-page-styles)
  (:import-from #:recurya/web/ui/csrf
                #:csrf-input)
  (:import-from #:recurya/web/i18n/core
                #:tr)
  (:export #:render-onboarding-handle-page))

(in-package #:recurya/web/ui/onboarding)

(defparameter *onboarding-extra-styles*
  ".auth-container .field { display: flex; flex-direction: column; gap: 0.4rem; }
.auth-container label { font-weight: 600; color: var(--color-text-dark); }
.auth-container input[type='text'] { width: 100%; box-sizing: border-box; }
.auth-container .hint { color: var(--color-text-muted); font-size: 0.85rem; line-height: 1.4; }
.auth-container .current-handle {
  background: var(--color-info-bg);
  color: var(--color-info-text);
  padding: 0.6rem 0.85rem;
  border-radius: 8px;
  font-size: 0.9rem;
  margin-bottom: 1rem;
}
.auth-container .current-handle code {
  background: rgba(3, 105, 161, 0.12);
  padding: 0.05rem 0.35rem;
  border-radius: 4px;
}
.auth-container .submit-row { margin-top: 0.5rem; }
.auth-container .submit-row .button-primary {
  width: 100%;
  padding: 0.85rem 1.5rem;
  border-radius: 999px;
}"
  "Extra page-specific styles for the onboarding handle form.")

(defun render-onboarding-handle-page (&key error suggested-handle)
  "Render the onboarding handle setup page.

Arguments:
  ERROR             - Optional error message string to display above the form.
  SUGGESTED-HANDLE  - The user's current handle (typically a placeholder)
                      to show as a hint and pre-fill the input value.

Returns:
  An HTML string suitable for an HTML response body.

The form posts to POST /onboarding/handle. CSRF protection is provided
by the standard middleware via RECURYA/WEB/UI/CSRF:CSRF-INPUT."
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head
      (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:title (tr :onboarding.page_title))
      (:style (:raw (auth-page-styles *onboarding-extra-styles*))))
     (:body
      (:div :class "auth-container"
            (:div :class "app-name" (tr :onboarding.app_name))
            (:h1 (tr :onboarding.heading))
            (:p :class "auth-help"
                (tr :onboarding.handle_help_1)
                (tr :onboarding.handle_help_2)
                (tr :onboarding.handle_help_3))
            (when suggested-handle
              (:div :class "current-handle"
                    (tr :onboarding.current_handle_prefix)
                    (:code suggested-handle)
                    (tr :onboarding.current_handle_suffix)))
            (when error
              (:div :class "error" error))
            (:form :method "post" :action "/onboarding/handle"
                   (:raw (or (csrf-input) ""))
                   (:div :class "field"
                         (:label :for "onboarding-handle" (tr :onboarding.field_label_handle))
                         (:input :id "onboarding-handle"
                                 :name "handle"
                                 :type "text"
                                 :value (or suggested-handle "")
                                 :required t
                                 :minlength "3"
                                 :maxlength "64"
                                 :pattern "[a-z0-9][a-z0-9-]{1,62}[a-z0-9]"
                                 :autocomplete "off"
                                 :autocapitalize "off"
                                 :spellcheck "false")
                         (:p :class "hint"
                             (tr :onboarding.field_hint)))
                   (:div :class "submit-row"
                         (:button :type "submit" :class "button-primary"
                                  (tr :onboarding.submit_button)))))))))
