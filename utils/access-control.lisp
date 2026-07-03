;;;; utils/access-control.lisp --- Centralised viewability rules.

(defpackage #:recurya/utils/access-control
  (:use #:cl)
  (:import-from #:recurya/db/notebooks
                #:notebook-status
                #:notebook-visibility
                #:notebook-author-id)
  (:import-from #:recurya/db/courses
                #:course-status
                #:course-visibility
                #:course-author-id)
  (:export #:can-view-notebook-p
           #:can-view-course-p
           #:course-member-visible-p
           #:publicly-listable-notebook-p
           #:publicly-listable-course-p))

(in-package #:recurya/utils/access-control)

(defun owner-of-notebook-p (user notebook)
  "Return T when USER (a session plist with :id) owns NOTEBOOK."
  (and user notebook
       (equal (princ-to-string (notebook-author-id notebook))
              (princ-to-string (getf user :id)))))

(defun can-view-notebook-p (user notebook)
  "Return T when USER may view NOTEBOOK.

Owner can always view their own notebook. Non-owners may view notebooks
whose status is \"published\" and whose visibility is \"public\" or
\"unlisted\" (unlisted = reachable by anyone with the URL, just hidden
from public listings). USER is a session plist with at least :id, or NIL
for an anonymous viewer."
  (cond
    ((null notebook) nil)
    ((owner-of-notebook-p user notebook) t)
    ((string/= "published" (notebook-status notebook)) nil)
    (t (let ((vis (notebook-visibility notebook)))
         (cond
           ((string= vis "public") t)
           ((string= vis "unlisted") t)
           ((string= vis "private") nil)
           (t nil))))))

(defun owner-of-course-p (user course)
  "Return T when USER (a session plist with :id) owns COURSE."
  (and user course
       (equal (princ-to-string (course-author-id course))
              (princ-to-string (getf user :id)))))

(defun can-view-course-p (user course)
  "Return T when USER may view COURSE.

Same rules as CAN-VIEW-NOTEBOOK-P: owner always; otherwise published and
visibility \"public\" or \"unlisted\"."
  (cond
    ((null course) nil)
    ((owner-of-course-p user course) t)
    ((string/= "published" (course-status course)) nil)
    (t (let ((vis (course-visibility course)))
         (cond
           ((string= vis "public") t)
           ((string= vis "unlisted") t)
           ((string= vis "private") nil)
           (t nil))))))

(defun publicly-listable-notebook-p (notebook)
  "Return T when NOTEBOOK is safe to surface in anonymous public listings."
  (and notebook
       (string= "published" (notebook-status notebook))
       (string= "public" (notebook-visibility notebook))))

(defun publicly-listable-course-p (course)
  "Return T when COURSE is safe to surface in anonymous public listings."
  (and course
       (string= "published" (course-status course))
       (string= "public" (course-visibility course))))

(defun course-member-visible-p (user notebook)
  "Return T when NOTEBOOK should be shown as a member of a course that
USER is currently viewing.

The course owner previewing their own course sees all of their own
notebooks — drafts, private, and unlisted included — so they can review
the whole course before publishing. Everyone else (anonymous or a
non-owner) sees only publicly-listable notebooks (published + public);
unlisted members stay hidden from non-owners, consistent with anonymous
course and notebook listings. Private notebooks never leak to non-owners."
  (and notebook
       (or (owner-of-notebook-p user notebook)
           (publicly-listable-notebook-p notebook))))
