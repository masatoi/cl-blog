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
  (:import-from #:recurya/web/ui/csrf
                #:csrf-input
                #:csrf-form-block)
  (:import-from #:recurya/web/i18n/core
                #:tr)
  (:export #:header
           #:header-styles
           #:page-shell
           #:format-timestamp
           #:icon
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
@media (min-width:640px) { .app-header__label { display:inline; } }
.app-header__auth-badge { color:rgba(248,250,252,0.65); font-size:0.85rem; font-weight:500; margin-right:0.25rem; }")

(defun header-styles ()
  "Return the CSS styles for the application header."
  *header-styles*)

(defun get-user-display (user)
  "Get the display name for a user."
  (let* ((name (getf user :name))
         (email (getf user :email))
         (display (or (and name (string/= name "") name)
                      (and email (string/= email "") email)
                      (tr :layout.auth.account_fallback))))
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

(defparameter *fa-icons*
  '(("pen-to-square" "0 0 512 512"
     "M471.6 21.7c-21.9-21.9-57.3-21.9-79.2 0L362.3 51.7l97.9 97.9 30.1-30.1c21.9-21.9 21.9-57.3 0-79.2L471.6 21.7zm-299.2 220c-6.1 6.1-10.8 13.6-13.5 21.9l-29.6 88.8c-2.9 8.6-.6 18.1 5.8 24.6s15.9 8.7 24.6 5.8l88.8-29.6c8.2-2.7 15.7-7.4 21.9-13.5L437.7 172.3 339.7 74.3 172.4 241.7zM96 64C43 64 0 107 0 160V416c0 53 43 96 96 96H352c53 0 96-43 96-96V320c0-17.7-14.3-32-32-32s-32 14.3-32 32v96c0 17.7-14.3 32-32 32H96c-17.7 0-32-14.3-32-32V160c0-17.7 14.3-32 32-32h96c17.7 0 32-14.3 32-32s-14.3-32-32-32H96z")
    ("trash" "0 0 448 512"
     "M135.2 17.7L128 32H32C14.3 32 0 46.3 0 64S14.3 96 32 96H416c17.7 0 32-14.3 32-32s-14.3-32-32-32H320l-7.2-14.3C307.4 6.8 296.3 0 284.2 0H163.8c-12.1 0-23.2 6.8-28.6 17.7zM416 128H32L53.2 467c1.6 25.3 22.6 45 47.9 45H346.9c25.3 0 46.3-19.7 47.9-45L416 128z")
    ("link" "0 0 640 512"
     "M579.8 267.7c56.5-56.5 56.5-148 0-204.5c-50-50-128.8-56.5-186.3-15.4l-1.6 1.1c-14.4 10.3-17.7 30.3-7.4 44.6s30.3 17.7 44.6 7.4l1.6-1.1c32.1-22.9 76-19.3 103.8 8.6c31.5 31.5 31.5 82.5 0 114L422.3 334.8c-31.5 31.5-82.5 31.5-114 0c-27.9-27.9-31.5-71.8-8.6-103.8l1.1-1.6c10.3-14.4 6.9-34.4-7.4-44.6s-34.4-6.9-44.6 7.4l-1.1 1.6C206.5 251.2 213 330 263 380c56.5 56.5 148 56.5 204.5 0L579.8 267.7zM60.2 244.3c-56.5 56.5-56.5 148 0 204.5c50 50 128.8 56.5 186.3 15.4l1.6-1.1c14.4-10.3 17.7-30.3 7.4-44.6s-30.3-17.7-44.6-7.4l-1.6 1.1c-32.1 22.9-76 19.3-103.8-8.6C81.5 371.8 81.5 320.8 113 289.3L217.7 184.6c31.5-31.5 82.5-31.5 114 0c27.9 27.9 31.5 71.8 8.6 103.9l-1.1 1.6c-10.3 14.4-6.9 34.4 7.4 44.6s34.4 6.9 44.6-7.4l1.1-1.6C433.5 260.8 427 182 377 132c-56.5-56.5-148-56.5-204.5 0L60.2 244.3z")
    ("arrow-left" "0 0 448 512"
     "M9.4 233.4c-12.5 12.5-12.5 32.8 0 45.3l160 160c12.5 12.5 32.8 12.5 45.3 0s12.5-32.8 0-45.3L109.2 288 416 288c17.7 0 32-14.3 32-32s-14.3-32-32-32l-306.7 0L214.6 118.6c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0l-160 160z")
    ("arrow-right" "0 0 448 512"
     "M438.6 278.6c12.5-12.5 12.5-32.8 0-45.3l-160-160c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3L338.8 224 32 224c-17.7 0-32 14.3-32 32s14.3 32 32 32l306.7 0L233.4 393.4c-12.5 12.5-12.5 32.8 0 45.3s32.8 12.5 45.3 0l160-160z"))
  "Font Awesome 6 (free, solid) icon geometry: (NAME viewBox path-data),
rendered inline by ICON so pages need no external icon font or CSS.")

(defun icon (name)
  "Return an inline SVG string for the Font Awesome (free, solid) glyph NAME
(a key in *FA-ICONS*), for embedding via (:raw ...). The glyph is sized in em
(scales with the surrounding font-size), coloured via currentColor, marked
aria-hidden, and carries class \"fa-icon\"."
  (let ((spec (cdr (assoc name *fa-icons* :test #'string=))))
    (unless spec
      (error "icon: unknown Font Awesome glyph ~S" name))
    (destructuring-bind (view-box path) spec
      (format nil
              "<svg class=\"fa-icon\" viewBox=\"~A\" fill=\"currentColor\" aria-hidden=\"true\"><path d=\"~A\"/></svg>"
              view-box path))))

(defun header (user)
  "Generate the application header HTML.

Renders the same top bar for everyone, with discovery links visible to
all visitors and account-related affordances gated on USER:

  Always:        Home (/), Notebooks (/notebooks), Courses (/courses)
  Logged-in:     My Notebooks (/dashboard/notebooks), My Courses
                 (/dashboard/courses) + avatar dropdown with
                 Account settings (/account) and Log out (POST /logout)
  Anonymous:     Login (/login)

The CSRF form block is emitted up-front so the logout form can pull
its token via hx-include without a separate fetch."
  (with-html-string (:raw (or (csrf-form-block) ""))
    (:header :class "app-header"
     (:div :class "app-header__inner"
      (:div :class "app-header__left"
       (:a :class "app-header__brand" :href "/" "Recurya")
       (:nav :class "app-header__nav"
        (:a :class "app-header__link" :href "/notebooks" (tr :layout.nav.notebooks))
        (:a :class "app-header__link" :href "/courses" (tr :layout.nav.courses))
        (when user
          (:a :class "app-header__link" :href "/dashboard/notebooks"
           (tr :layout.nav.my_notebooks)))
        (when user
          (:a :class "app-header__link" :href "/dashboard/courses"
           (tr :layout.nav.my_courses)))))
      (cond
        (user
         (let ((display (get-user-display user))
               (initial (get-user-initial user)))
           (:details :class "app-header__menu" :data-testid "app-header-menu"
            (:summary :class "app-header__summary"
             (:span :class "app-header__avatar" initial)
             (:span :class "app-header__label" display)
             (:span :class "app-header__chevron" "v"))
            (:div :class "app-header__panel"
             (:a :class "app-header__action" :href "/account" (tr :layout.menu.account))
             (:form :method "post" :action "/logout" (:raw (or (csrf-input) ""))
              (:button :type "submit" :class "app-header__action" (tr :layout.menu.logout)))))))
        (t
         (:span :class "app-header__auth-badge" (tr :layout.auth.badge_anon))
         (:a :class "app-header__link" :href "/login" (tr :layout.auth.login))))))))

(defun page-shell (&key title styles user body-content head-extras body-scripts)
  "Generate a complete HTML page shell.

The site header is rendered for all visitors (anonymous users see Login,
authenticated users see Dashboard and the account dropdown). The
body-content is wrapped in a <main> element for proper layout and margins.

HEAD-EXTRAS is an optional HTML string injected at the end of <head>
(e.g. editor-head-tags for the CodeMirror setup).
BODY-SCRIPTS is an optional HTML string injected just before </body>
(e.g. a <script src=\"/static/js/learn.js\"> tag)."
  (spinneret:with-html-string
    (:doctype)
    (:html
     (:head (:meta :charset "utf-8")
      (:meta :name "viewport" :content "width=device-width, initial-scale=1")
      (:title title)
      (:script :src "https://unpkg.com/htmx.org@2.0.4" :integrity
       "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+"
       :crossorigin "anonymous")
      (:style (:raw (header-styles)))
      (when styles (:style (:raw styles)))
      (when head-extras (:raw head-extras)))
     (:body (:raw (header user)) (:main (:raw body-content))
      (when body-scripts (:raw body-scripts))))))
