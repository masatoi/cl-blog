;;;; tests/web/profile.lisp --- Tests for the public @handle profile page.

(defpackage #:recurya/tests/web/profile
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db
                #:create-test-user)
  (:import-from #:recurya/web/routes
                #:profile-handler)
  (:import-from #:recurya/db/notebooks
                #:create-notebook!)
  (:import-from #:recurya/db/courses
                #:create-course!)
  (:import-from #:local-time))

(in-package #:recurya/tests/web/profile)

;;; --- helpers ---

(defmacro with-mock-session (session-hash &body body)
  `(let ((ningle/context:*session* ,session-hash))
     ,@body))

(defun make-session (&key user)
  (let ((ht (make-hash-table)))
    (when user (setf (gethash :user ht) user))
    ht))

(defun response-status (response) (first response))
(defun response-body (response) (third response))

;;; --- tests ---

(deftest profile-handler-404-for-unknown-handle
  (with-test-db
    (with-mock-session (make-session)
      (let ((res (profile-handler '((:captures . ("nobody-7b"))))))
        (ok (= 404 (response-status res)))))))

(deftest profile-handler-renders-handle-and-display-name
  (with-test-db
    (let ((dao (create-test-user :email-prefix "prof"
                                 :display-name "Prof Author"
                                 :handle "prof-7b")))
      (declare (ignore dao))
      (with-mock-session (make-session)
        (let* ((res (profile-handler '((:captures . ("prof-7b")))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "@prof-7b" body))
          (ok (search "Prof Author" body)))))))

(deftest profile-handler-lists-public-published-notebooks
  (with-test-db
    (let ((dao (create-test-user :email-prefix "lister"
                                 :handle "lister-7b")))
      (create-notebook! :title "Public Pub" :slug "public-pub"
                        :body-md "===prose===
hi"
                        :cells nil :author dao
                        :status "published" :visibility "public"
                        :published-at (local-time:now))
      (with-mock-session (make-session)
        (let* ((res (profile-handler '((:captures . ("lister-7b")))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Public Pub" body))
          ;; Card link points at /@lister-7b/public-pub
          (ok (search "/@lister-7b/public-pub" body)))))))

(deftest profile-handler-excludes-draft-and-private-notebooks
  (with-test-db
    (let ((dao (create-test-user :email-prefix "hider"
                                 :handle "hider-7b")))
      (create-notebook! :title "Draft NB" :slug "drafty"
                        :body-md "===prose===
hi"
                        :cells nil :author dao
                        :status "draft")
      (create-notebook! :title "Pub Priv" :slug "pubpriv"
                        :body-md "===prose===
hi"
                        :cells nil :author dao
                        :status "published" :visibility "private"
                        :published-at (local-time:now))
      (with-mock-session (make-session)
        (let* ((res (profile-handler '((:captures . ("hider-7b")))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ng (search "Draft NB" body))
          (ng (search "Pub Priv" body))
          (ok (search "No public notebooks" body)))))))

(deftest profile-handler-excludes-other-authors-notebooks
  (with-test-db
    (let ((alice (create-test-user :email-prefix "alice-p"
                                   :handle "alice-p7b"))
          (bob (create-test-user :email-prefix "bob-p"
                                 :handle "bob-p7b")))
      (declare (ignore bob))
      (create-notebook! :title "Alice nb" :slug "alice-nb"
                        :body-md "===prose===
a"
                        :cells nil :author alice
                        :status "published" :visibility "public"
                        :published-at (local-time:now))
      (with-mock-session (make-session)
        (let* ((res (profile-handler '((:captures . ("bob-p7b")))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ng (search "Alice nb" body)))))))

(deftest profile-handler-lists-public-published-courses
  (with-test-db
    (let ((dao (create-test-user :email-prefix "course-author"
                                 :handle "ca-7b")))
      (create-course! :title "Public Course" :slug "public-course"
                      :status "published" :visibility "public"
                      :published-at (local-time:now) :author dao)
      (with-mock-session (make-session)
        (let* ((res (profile-handler '((:captures . ("ca-7b")))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Public Course" body))
          (ok (search "/c/@ca-7b/public-course" body)))))))
