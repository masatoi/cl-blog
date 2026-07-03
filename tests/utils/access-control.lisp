;;;; tests/utils/access-control.lisp --- Tests for recurya/utils/access-control.

(defpackage #:recurya/tests/utils/access-control
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db
                #:create-test-user)
  (:import-from #:recurya/db/users
                #:users-id)
  (:import-from #:recurya/db/notebooks
                #:create-notebook!
                #:update-notebook!
                #:notebook-id)
  (:import-from #:recurya/db/courses
                #:create-course!
                #:update-course!
                #:course-id)
  (:import-from #:recurya/utils/access-control
                #:can-view-notebook-p
                #:can-view-course-p
                #:course-member-visible-p
                #:publicly-listable-notebook-p
                #:publicly-listable-course-p))

(in-package #:recurya/tests/utils/access-control)

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun mk-user-plist (dao)
  "Build the session-style plist that handlers pass around."
  (list :id (users-id dao) :role :user))

(defun mk-notebook (author-dao &key (status "draft") (visibility "private"))
  "Create a notebook DAO owned by AUTHOR-DAO with given STATUS/VISIBILITY."
  (let ((nb (create-notebook!
             :title (format nil "NB ~A-~A" status visibility)
             :body-md "===prose===
hi"
             :cells nil
             :author author-dao
             :status status
             :visibility visibility)))
    ;; The status default branch in create-notebook! always sets status,
    ;; but make sure visibility round-trips by re-saving via update.
    (update-notebook! (notebook-id nb)
                      :status status
                      :visibility visibility)
    nb))

(defun mk-course (author-dao &key (status "draft") (visibility "private"))
  "Create a course DAO owned by AUTHOR-DAO with given STATUS/VISIBILITY."
  (let ((c (create-course! :title (format nil "C ~A-~A" status visibility)
                           :status status
                           :visibility visibility
                           :author author-dao)))
    (update-course! (course-id c)
                    :status status
                    :visibility visibility)
    c))

;;; ============================================================
;;; can-view-notebook-p
;;; ============================================================

(deftest can-view-notebook-published-public
  (testing "published+public notebooks are visible to everyone"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (owner (mk-user-plist owner-dao))
             (other (mk-user-plist other-dao))
             (nb (mk-notebook owner-dao
                              :status "published"
                              :visibility "public")))
        (ok (can-view-notebook-p owner nb) "owner can view")
        (ok (can-view-notebook-p other nb) "other user can view")
        (ok (can-view-notebook-p nil nb)   "anonymous can view")))))

(deftest can-view-notebook-published-private
  (testing "published+private notebooks are visible only to the owner"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (owner (mk-user-plist owner-dao))
             (other (mk-user-plist other-dao))
             (nb (mk-notebook owner-dao
                              :status "published"
                              :visibility "private")))
        (ok      (can-view-notebook-p owner nb) "owner can view")
        (ok (not (can-view-notebook-p other nb)) "other user blocked")
        (ok (not (can-view-notebook-p nil nb))   "anonymous blocked")))))

(deftest can-view-notebook-draft-any-visibility
  (testing "draft notebooks are visible only to the owner regardless of visibility"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (owner (mk-user-plist owner-dao))
             (other (mk-user-plist other-dao))
             (draft-private (mk-notebook owner-dao
                                         :status "draft"
                                         :visibility "private"))
             (draft-public (mk-notebook owner-dao
                                        :status "draft"
                                        :visibility "public")))
        (ok      (can-view-notebook-p owner draft-private) "owner sees own draft (private)")
        (ok (not (can-view-notebook-p other draft-private)) "other blocked from draft (private)")
        (ok (not (can-view-notebook-p nil draft-private))   "anon blocked from draft (private)")
        (ok      (can-view-notebook-p owner draft-public)  "owner sees own draft (public)")
        (ok (not (can-view-notebook-p other draft-public)) "other blocked from draft (public)")
        (ok (not (can-view-notebook-p nil draft-public))   "anon blocked from draft (public)")))))

(deftest can-view-notebook-nil-notebook
  (testing "nil notebook is never viewable"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (owner (mk-user-plist owner-dao)))
        (ok (not (can-view-notebook-p owner nil)))
        (ok (not (can-view-notebook-p nil nil)))))))

;;; ============================================================
;;; publicly-listable-notebook-p
;;; ============================================================

(deftest publicly-listable-notebook-matrix
  (testing "only published+public notebooks are publicly listable"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (pub-pub (mk-notebook owner-dao
                                   :status "published"
                                   :visibility "public"))
             (pub-priv (mk-notebook owner-dao
                                    :status "published"
                                    :visibility "private"))
             (draft-pub (mk-notebook owner-dao
                                     :status "draft"
                                     :visibility "public"))
             (draft-priv (mk-notebook owner-dao
                                      :status "draft"
                                      :visibility "private")))
        (ok      (publicly-listable-notebook-p pub-pub)   "published+public listed")
        (ok (not (publicly-listable-notebook-p pub-priv)) "published+private hidden")
        (ok (not (publicly-listable-notebook-p draft-pub))  "draft+public hidden")
        (ok (not (publicly-listable-notebook-p draft-priv)) "draft+private hidden")
        (ok (not (publicly-listable-notebook-p nil))        "nil hidden")))))

;;; ============================================================
;;; can-view-course-p
;;; ============================================================

(deftest can-view-course-published-public
  (testing "published+public courses are visible to everyone"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (owner (mk-user-plist owner-dao))
             (other (mk-user-plist other-dao))
             (c (mk-course owner-dao
                           :status "published"
                           :visibility "public")))
        (ok (can-view-course-p owner c) "owner can view")
        (ok (can-view-course-p other c) "other user can view")
        (ok (can-view-course-p nil c)   "anonymous can view")))))

(deftest can-view-course-published-private
  (testing "published+private courses are visible only to the owner"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (owner (mk-user-plist owner-dao))
             (other (mk-user-plist other-dao))
             (c (mk-course owner-dao
                           :status "published"
                           :visibility "private")))
        (ok      (can-view-course-p owner c) "owner can view")
        (ok (not (can-view-course-p other c)) "other user blocked")
        (ok (not (can-view-course-p nil c))   "anonymous blocked")))))

(deftest can-view-course-draft-any-visibility
  (testing "draft courses are visible only to the owner regardless of visibility"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (owner (mk-user-plist owner-dao))
             (other (mk-user-plist other-dao))
             (draft-private (mk-course owner-dao
                                       :status "draft"
                                       :visibility "private"))
             (draft-public (mk-course owner-dao
                                      :status "draft"
                                      :visibility "public")))
        (ok      (can-view-course-p owner draft-private) "owner sees own draft (private)")
        (ok (not (can-view-course-p other draft-private)) "other blocked from draft (private)")
        (ok (not (can-view-course-p nil draft-private))   "anon blocked from draft (private)")
        (ok      (can-view-course-p owner draft-public)  "owner sees own draft (public)")
        (ok (not (can-view-course-p other draft-public)) "other blocked from draft (public)")
        (ok (not (can-view-course-p nil draft-public))   "anon blocked from draft (public)")))))

(deftest can-view-course-nil-course
  (testing "nil course is never viewable"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (owner (mk-user-plist owner-dao)))
        (ok (not (can-view-course-p owner nil)))
        (ok (not (can-view-course-p nil nil)))))))

;;; ============================================================
;;; publicly-listable-course-p
;;; ============================================================

(deftest publicly-listable-course-matrix
  (testing "only published+public courses are publicly listable"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (pub-pub (mk-course owner-dao
                                 :status "published"
                                 :visibility "public"))
             (pub-priv (mk-course owner-dao
                                  :status "published"
                                  :visibility "private"))
             (draft-pub (mk-course owner-dao
                                   :status "draft"
                                   :visibility "public"))
             (draft-priv (mk-course owner-dao
                                    :status "draft"
                                    :visibility "private")))
        (ok      (publicly-listable-course-p pub-pub)   "published+public listed")
        (ok (not (publicly-listable-course-p pub-priv)) "published+private hidden")
        (ok (not (publicly-listable-course-p draft-pub))  "draft+public hidden")
        (ok (not (publicly-listable-course-p draft-priv)) "draft+private hidden")
        (ok (not (publicly-listable-course-p nil))        "nil hidden")))))

(deftest can-view-notebook-published-unlisted
  (testing "published+unlisted notebooks are viewable by anyone with the URL"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (owner (mk-user-plist owner-dao))
             (other (mk-user-plist other-dao))
             (nb (mk-notebook owner-dao
                              :status "published"
                              :visibility "unlisted")))
        (ok (can-view-notebook-p owner nb) "owner can view")
        (ok (can-view-notebook-p other nb) "other user can view")
        (ok (can-view-notebook-p nil nb)   "anonymous can view")))))

(deftest unlisted-notebook-not-publicly-listable
  (testing "unlisted notebooks are excluded from public listings"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (nb (mk-notebook owner-dao
                              :status "published"
                              :visibility "unlisted")))
        (ng (publicly-listable-notebook-p nb))))))

(deftest can-view-course-published-unlisted
  (testing "published+unlisted courses are viewable by anyone with the URL"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (owner (mk-user-plist owner-dao))
             (other (mk-user-plist other-dao))
             (c (mk-course owner-dao
                           :status "published"
                           :visibility "unlisted")))
        (ok (can-view-course-p owner c) "owner can view")
        (ok (can-view-course-p other c) "other user can view")
        (ok (can-view-course-p nil c)   "anonymous can view")))))

(deftest unlisted-course-not-publicly-listable
  (testing "unlisted courses are excluded from public listings"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (c (mk-course owner-dao
                           :status "published"
                           :visibility "unlisted")))
        (ng (publicly-listable-course-p c))))))

(deftest course-member-visible-owner-sees-all-own
  (testing "the course owner sees ALL their own notebooks as course
members — published+public/private/unlisted and drafts — for preview"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (owner (mk-user-plist owner-dao))
             (pub-pub (mk-notebook owner-dao
                                   :status "published" :visibility "public"))
             (pub-priv (mk-notebook owner-dao
                                    :status "published" :visibility "private"))
             (pub-unl (mk-notebook owner-dao
                                   :status "published" :visibility "unlisted"))
             (draft-priv (mk-notebook owner-dao
                                      :status "draft" :visibility "private")))
        (ok (course-member-visible-p owner pub-pub)    "owner sees published+public")
        (ok (course-member-visible-p owner pub-priv)   "owner sees published+private")
        (ok (course-member-visible-p owner pub-unl)    "owner sees published+unlisted")
        (ok (course-member-visible-p owner draft-priv) "owner sees own draft")))))

(deftest course-member-visible-nonowner-sees-public-only
  (testing "non-owners and anonymous viewers see only published+public
course members; unlisted, private, and drafts stay hidden"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (other-dao (create-test-user :email-prefix "other"))
             (other (mk-user-plist other-dao))
             (pub-pub (mk-notebook owner-dao
                                   :status "published" :visibility "public"))
             (pub-priv (mk-notebook owner-dao
                                    :status "published" :visibility "private"))
             (pub-unl (mk-notebook owner-dao
                                   :status "published" :visibility "unlisted"))
             (draft-pub (mk-notebook owner-dao
                                     :status "draft" :visibility "public")))
        (ok      (course-member-visible-p other pub-pub)   "other sees published+public")
        (ok (not (course-member-visible-p other pub-priv)) "other blocked from private")
        (ok (not (course-member-visible-p other pub-unl))  "other blocked from unlisted")
        (ok (not (course-member-visible-p other draft-pub)) "other blocked from draft")
        (ok      (course-member-visible-p nil pub-pub)   "anon sees published+public")
        (ok (not (course-member-visible-p nil pub-priv)) "anon blocked from private")
        (ok (not (course-member-visible-p nil pub-unl))  "anon blocked from unlisted")
        (ok (not (course-member-visible-p nil draft-pub)) "anon blocked from draft")))))

(deftest course-member-visible-nil-notebook
  (testing "nil notebook is never a visible course member"
    (with-test-db
      (let* ((owner-dao (create-test-user :email-prefix "owner"))
             (owner (mk-user-plist owner-dao)))
        (ng (course-member-visible-p owner nil))
        (ng (course-member-visible-p nil nil))))))
