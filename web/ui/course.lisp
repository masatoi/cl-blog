;;;; web/ui/course.lisp --- Public single-course view (/c/:slug).

(defpackage #:recurya/web/ui/course
  (:use #:cl)
  (:import-from #:spinneret #:with-html-string)
  (:import-from #:recurya/web/ui/layout #:page-shell)
  (:import-from #:recurya/web/i18n/core
                #:tr)
  (:export #:render))

(in-package #:recurya/web/ui/course)

(defparameter *styles*
  "/* Public course detail styles */
body { font-family: 'Inter', -apple-system, BlinkMacSystemFont,
                    'Segoe UI', Roboto, sans-serif;
       margin: 0; background: #f8fafc; color: #0f172a; line-height: 1.6; }
main { max-width: 760px; margin: 0 auto; padding: 3rem 1.5rem 4rem; }
.course-header { text-align: center; margin-bottom: 2.5rem; }
.course-header h1 { font-size: 2.4rem; letter-spacing: -0.03em;
                    margin: 0 0 0.5rem; }
.course-header p.summary { color: #475569; font-size: 1.05rem;
                           max-width: 620px; margin: 0 auto; }
.draft-banner { max-width: 720px; margin: 0 auto 2rem;
                background: #fef3c7; color: #92400e;
                border: 1px solid #fbbf24;
                border-radius: 8px; padding: 0.75rem 1rem;
                font-size: 0.9rem; text-align: center; }
.nb-card { background: #fff; border-radius: 12px;
           box-shadow: 0 1px 3px rgba(0,0,0,0.08);
           padding: 1.5rem 1.75rem; margin-bottom: 1.25rem;
           transition: box-shadow 0.15s ease; }
.nb-card:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.12); }
.nb-card__index { color: #94a3b8; font-size: 0.8rem;
                  font-weight: 600; letter-spacing: 0.04em;
                  text-transform: uppercase; margin-bottom: 0.4rem; }
.nb-card__title { margin: 0 0 0.5rem; font-size: 1.25rem;
                  letter-spacing: -0.02em; }
.nb-card__title a { color: #0f172a; text-decoration: none; }
.nb-card__title a:hover { color: #0ea5e9; }
.nb-card__summary { color: #475569; line-height: 1.6;
                    margin: 0 0 0.85rem; }
.nb-card__progress { color: #64748b; font-size: 0.85rem; }
.nb-card__open { color: #0ea5e9; font-weight: 600; text-decoration: none;
                 font-size: 0.9rem; }
.nb-card__open:hover { text-decoration: underline; }
.empty { text-align: center; color: #64748b; padding: 3rem 0; }")

(defun %passed-count (slug passed-by-notebook)
  "Look up the number of passed cells for SLUG in PASSED-BY-NOTEBOOK alist.
Returns 0 when slug is missing or value is nil."
  (let ((entry (assoc slug passed-by-notebook :test #'equal)))
    (or (cdr entry) 0)))

(defun render (&key course notebooks user passed-by-notebook noindex)
  "Render the public course detail page.

COURSE is a plist with :slug :title :summary :status.
NOTEBOOKS is a list of plists with :slug :title :summary :position
:author-handle. The :author-handle of each attached notebook is used
to build the /@<handle>/<slug> link; notebooks without an author-handle
render the title as plain text.
USER is the current session plist (or nil when anonymous).
PASSED-BY-NOTEBOOK is an alist mapping notebook-slug -> integer,
the count of cells the current user has passed for that notebook.
Empty alist is treated as no progress."
  (let* ((title (getf course :title))
         (summary (getf course :summary))
         (status (getf course :status))
         (draft-p (string= status "draft")))
    (page-shell
     :title (or title (tr :course.page_title_fallback))
     :styles *styles*
     :user user
     :head-extras (when noindex
                    "<meta name=\"robots\" content=\"noindex\">")
     :body-content
     (with-html-string
       (when draft-p
         (:div :class "draft-banner"
               (tr :course.draft_banner)))
       (:div :class "course-header"
             (:h1 (or title (tr :course.untitled)))
             (when (and summary (string/= summary ""))
               (:p :class "summary" summary)))
       (cond
         ((null notebooks)
          (:p :class "empty"
              (tr :course.empty_notebooks)))
         (t
          (dolist (nb notebooks)
            (let* ((slug (getf nb :slug))
                   (nb-title (getf nb :title))
                   (nb-summary (getf nb :summary))
                   (position (getf nb :position))
                   (author-handle (getf nb :author-handle))
                   (passed (%passed-count slug passed-by-notebook))
                   (course-slug (getf course :slug))
                   (href (when (and author-handle slug)
                           (if course-slug
                               (format nil "/@~A/~A?course=~A"
                                       author-handle slug course-slug)
                               (format nil "/@~A/~A"
                                       author-handle slug)))))
              (:div :class "nb-card"
                    (when position
                      (:div :class "nb-card__index"
                            (tr :course.notebook_index
                                (1+ position))))
                    (:h2 :class "nb-card__title"
                         (if href
                             (:a :href href nb-title)
                             (:span nb-title)))
                    (when (and nb-summary (string/= nb-summary ""))
                      (:p :class "nb-card__summary" nb-summary))
                    (:div :class "nb-card__progress"
                          (tr :course.passed_count passed))
                    (when href
                      (:a :class "nb-card__open"
                          :href href (tr :course.open_notebook))))))))))))
