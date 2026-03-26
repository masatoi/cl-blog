;;;; web/ui/layout.lisp --- Shared page layout: header, page shell, styles.
;;;;
;;;; Provides the application header (with nav, user menu, logout) and
;;;; page-shell for wrapping authenticated pages in a consistent layout.
;;;; User plist shape: (:id :email :name :language :timezone).

(defpackage #:recurya/web/ui/layout
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/styles
                #:common-styles
                #:page-styles)
  (:export #:header
           #:header-styles
           #:page-shell
           #:format-timestamp
           ;; Re-export from styles
           #:common-styles
           #:page-styles))

(in-package #:recurya/web/ui/layout)

(defparameter *header-styles*
  ".app-header { background:#0f172a; color:#f8fafc; }
.app-header__inner { max-width:1080px; margin:0 auto; padding:1rem 1.5rem; display:flex; align-items:center; justify-content:space-between; gap:1.5rem; }
.app-header__left { display:flex; align-items:center; gap:1.5rem; min-width:0; }
.app-header__brand { color:#f8fafc; font-weight:700; letter-spacing:-0.02em; text-decoration:none; font-size:1.2rem; }
.app-header__nav { display:flex; align-items:center; gap:1rem; }
.app-header__link { color:rgba(248,250,252,0.82); text-decoration:none; font-weight:600; font-size:0.95rem; }
.app-header__link:hover { color:#38bdf8; }
.app-header__menu { position:relative; }
.app-header__summary { list-style:none; display:inline-flex; align-items:center; gap:0.5rem; cursor:pointer; border-radius:999px; padding:0.45rem 0.95rem; background:rgba(241,245,249,0.08); color:#f8fafc; border:1px solid rgba(148,163,184,0.35); font-weight:600; }
.app-header__summary::-webkit-details-marker { display:none; }
.app-header__summary:focus { outline:2px solid #38bdf8; outline-offset:2px; }
.app-header__chevron { font-size:0.8rem; opacity:0.85; }
.app-header__menu[open] .app-header__summary { border-color:#38bdf8; background:rgba(56,189,248,0.2); }
.app-header__panel { position:absolute; right:0; margin-top:0.55rem; background:#fff; color:#0f172a; border-radius:12px; box-shadow:0 18px 48px rgba(15,23,42,0.28); min-width:180px; padding:0.75rem; z-index:40; display:flex; flex-direction:column; gap:0.5rem; }
.app-header__panel form { margin:0; }
.app-header__action { width:100%; padding:0.65rem 0.9rem; border:none; border-radius:8px; background:#f1f5f9; color:#0f172a; font-weight:600; cursor:pointer; text-align:left; transition:background 0.12s ease; }
.app-header__action:hover { background:#e2e8f0; }
.app-header__avatar { display:inline-flex; align-items:center; justify-content:center; width:28px; height:28px; border-radius:999px; background:#38bdf8; color:#0f172a; font-weight:700; }
.app-header__label { display:none; font-size:0.95rem; }
@media (min-width:640px) { .app-header__label { display:inline; } }")

(defun header-styles ()
  "Return the CSS styles for the application header."
  *header-styles*)

(defun get-user-display (user)
  "Get the display name for a user."
  (let* ((name (getf user :name))
         (email (getf user :email))
         (display (or (and name (string/= name "") name)
                      (and email (string/= email "") email)
                      "Account")))
    display))

(defun get-user-initial (user)
  "Get the first letter of the user's display name."
  (let* ((display (get-user-display user))
         (first-word (first (uiop:split-string display :separator '(#\Space))))
         (initial (if (and first-word (> (length first-word) 0))
                      (string-upcase (subseq first-word 0 1))
                      "A")))
    initial))

(defun format-timestamp (timestamp &optional timezone-name)
  "Format TIMESTAMP as 'YYYY-MM-DD HH:MM' in the specified TIMEZONE-NAME.
   TIMEZONE-NAME should be a string like 'Asia/Tokyo', 'America/New_York', or 'UTC'.
   If TIMEZONE-NAME is nil or invalid, defaults to UTC."
  (when timestamp
    (handler-case
        (let* ((tz-name (or timezone-name "UTC"))
               ;; Try to find the timezone, falling back to UTC if not found
               (timezone (or (local-time:find-timezone-by-location-name tz-name)
                             local-time:+utc-zone+))
               (adjusted-timestamp
                 (if (typep timestamp 'local-time:timestamp)
                     timestamp
                     ;; Handle case where timestamp might be a string or other type
                     (local-time:parse-timestring (princ-to-string timestamp)))))
          (local-time:format-timestring
           nil adjusted-timestamp
           :format '(:year "-" (:month 2) "-" (:day 2) " " (:hour 2) ":" (:min 2))
           :timezone timezone))
      (error ()
        ;; Fallback: format in UTC if timezone lookup fails
        (handler-case
            (let ((ts (if (typep timestamp 'local-time:timestamp)
                          timestamp
                          (local-time:parse-timestring (princ-to-string timestamp)))))
              (local-time:format-timestring
               nil ts
               :format '(:year "-" (:month 2) "-" (:day 2) " " (:hour 2) ":" (:min 2))
               :timezone local-time:+utc-zone+))
          (error ()
            ;; Last resort: return the string representation
            (princ-to-string timestamp)))))))

(defun header (user)
  "Generate the application header HTML."
  (let ((display (get-user-display user))
        (initial (get-user-initial user)))
    (spinneret:with-html-string
      (:header :class "app-header"
        (:div :class "app-header__inner"
          (:div :class "app-header__left"
            (:a :class "app-header__brand" :href "/posts" "Recurya")
            (:nav :class "app-header__nav"
              (:a :class "app-header__link" :href "/blog" "Blog")
              (:a :class "app-header__link" :href "/posts" "Posts")))
          (:details :class "app-header__menu" :data-testid "app-header-menu"
            (:summary :class "app-header__summary"
              (:span :class "app-header__avatar" initial)
              (:span :class "app-header__label" display)
              (:span :class "app-header__chevron" "v"))
            (:div :class "app-header__panel"
              (:a :class "app-header__action" :href "/account" "Account settings")
              (:form :method "post" :action "/logout"
                (:button :type "submit" :class "app-header__action" "Log out")))))))))

(defun page-shell (&key title styles user body-content)
  "Generate a complete HTML page shell with optional header for authenticated users.

The body-content is wrapped in a <main> element for proper layout and margins."
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:title title)
      (:script :src "https://unpkg.com/htmx.org@2.0.4"
       :integrity "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
       :crossorigin "anonymous")
      (when user (:style (:raw (header-styles))))
      (when styles (:style (:raw styles))))
     (:body (when user (:raw (header user)))
      (:main (:raw body-content))))))
