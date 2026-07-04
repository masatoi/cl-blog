;;;; tests/web/notebook-routes.lisp --- Tests for notebook route handlers.

(defpackage #:recurya/tests/web/notebook-routes
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db
                #:create-test-user)
  (:import-from #:recurya/web/routes
                #:notebooks-handler
                #:notebook-new-handler
                #:notebook-create-handler
                #:notebook-edit-handler
                #:notebook-update-handler
                #:notebook-set-state-handler
                #:notebook-confirm-delete-handler
                #:notebook-delete-handler
                #:notebooks-public-handler
                #:public-notebook-by-handle-handler
                #:public-notebook-cell-run-by-handle-handler
                #:profile-handler)
  (:import-from #:recurya/db/users
                #:get-user-by-id
                #:users-id
                #:users-handle
                #:users-display-name)
  (:import-from #:recurya/db/notebooks
                #:create-notebook!
                #:get-notebook-by-id
                #:get-notebook-by-slug
                #:notebook-id
                #:notebook-title
                #:notebook-body-md
                #:notebook-status
                #:notebook-visibility)
  (:import-from #:recurya/db/courses
                #:create-course!
                #:course-id
                #:course-slug
                #:course-title)
  (:import-from #:recurya/db/course-notebooks
                #:add-notebook-to-course!)
  (:import-from #:uuid
                #:make-v4-uuid))

(in-package #:recurya/tests/web/notebook-routes)

;;; --- helpers ---

(defmacro with-mock-session (session-hash &body body)
  `(let ((ningle/context:*session* ,session-hash))
     ,@body))

(defmacro with-mock-request ((&key htmx) &body body)
  "Bind ningle/context:*request* to a mock Lack request. When HTMX is true the
HX-Request header is included so htmx-request-p returns T."
  `(let* ((headers (make-hash-table :test 'equal))
          (env (append (list :request-method :get
                             :path-info "/test"
                             :headers headers)
                       (when ,htmx (list :http-hx-request "true"))))
          (ningle/context:*request* (lack/request:make-request env)))
     ,@body))

(defun make-session (&key user)
  (let ((ht (make-hash-table)))
    (when user (setf (gethash :user ht) user))
    ht))

(defun response-status (response) (first response))
(defun response-headers (response) (second response))
(defun response-body (response) (third response))
(defun response-location (response)
  (getf (response-headers response) :location))

(defun mk-user ()
  "Create a test user and return the session plist used by handlers."
  (let ((dao (create-test-user :email-prefix "nb-route")))
    (list :id (users-id dao)
          :email (format nil "nb-route-~A@example.com" (make-v4-uuid))
          :name (users-display-name dao)
          :handle (users-handle dao)
          :role :user
          :provider "google"
          :timezone "UTC"
          :language "en")))

;;; --- new / create ---

(deftest new-handler-redirects-anonymous
  (with-mock-session (make-session)
    (let ((res (notebook-new-handler nil)))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest new-handler-renders-form-for-user
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((res (notebook-new-handler nil)))
          (ok (= 200 (response-status res)))
          (ok (search "New Notebook" (first (response-body res)))))))))

(deftest create-handler-redirects-anonymous
  (with-mock-session (make-session)
    (let ((res (notebook-create-handler '(("title" . "x")))))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest create-handler-rejects-blank-title
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-create-handler
                     '(("title" . "") ("body" . "===prose===
hi"))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Title is required" body)))))))

(deftest create-handler-validation-error-preserves-cells-json
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-create-handler
                     (list (cons "title" "")
                           (cons "body" "===prose===
hi

===eval===
(+ 1 2)")
                           (cons "status" "draft")
                           (cons "visibility" "private"))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "data-cells=" body)
              "re-rendered form still embeds a data-cells attribute")
          (ok (search "code-eval" body)
              "submitted eval cell survives the validation re-render"))))))

(deftest create-handler-rejects-blank-body
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-create-handler
                     '(("title" . "T1") ("body" . ""))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Body is required" body)))))))

(deftest create-handler-shows-parser-errors
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-create-handler
                     '(("title" . "Bad") ("body" . "===banana===
peel"))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Validation errors" body)))))))

(deftest create-handler-persists-and-redirects
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((params '(("title" . "My NB")
                         ("slug" . "")
                         ("summary" . "")
                         ("body" . "===prose===
Hello.")
                         ("status" . "draft")))
               (res (notebook-create-handler params)))
          (ok (= 302 (response-status res)))
          (ok (string= "/dashboard/notebooks" (response-location res)))
          (let ((nb (get-notebook-by-slug "my-nb")))
            (ok nb)
            (ok (string= "My NB" (notebook-title nb)))
            (ok (string= "draft" (notebook-status nb)))))))))

(deftest create-handler-published-sets-published-at
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((params '(("title" . "Pub NB")
                        ("slug" . "")
                        ("summary" . "")
                        ("body" . "===prose===
hi")
                        ("status" . "published"))))
          (notebook-create-handler params)
          (let ((nb (get-notebook-by-slug "pub-nb")))
            (ok nb)
            (ok (string= "published" (notebook-status nb)))
            (ok (recurya/db/notebooks:notebook-published-at nb))))))))

(deftest new-handler-form-has-visibility-select
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-new-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "name=visibility" body)
              "form has a visibility select")
          (ok (search "value=private" body)
              "private option is rendered")
          (ok (search "value=public" body)
              "public option is rendered"))))))

(deftest create-handler-persists-visibility-public
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((params '(("title" . "Vis NB")
                        ("slug" . "")
                        ("summary" . "")
                        ("body" . "===prose===
hi")
                        ("status" . "published")
                        ("visibility" . "public"))))
          (notebook-create-handler params)
          (let ((nb (get-notebook-by-slug "vis-nb")))
            (ok nb)
            (ok (string= "public" (notebook-visibility nb)))))))))

(deftest create-handler-defaults-visibility-private
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((params '(("title" . "Default Priv")
                        ("slug" . "")
                        ("summary" . "")
                        ("body" . "===prose===
hi")
                        ("status" . "draft"))))
          (notebook-create-handler params)
          (let ((nb (get-notebook-by-slug "default-priv")))
            (ok nb)
            (ok (string= "private" (notebook-visibility nb))
                "absent visibility param defaults to private")))))))

;;; --- listing ---

(deftest list-handler-redirects-anonymous
  (with-mock-session (make-session)
    (let ((res (notebooks-handler nil)))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest list-handler-shows-own-only
  (with-test-db
    (let* ((alice (mk-user))
           (bob   (mk-user))
           (alice-dao (get-user-by-id (getf alice :id)))
           (bob-dao   (get-user-by-id (getf bob :id))))
      (create-notebook!
       :title "Alice NB" :body-md "===prose===
a" :cells '() :author alice-dao)
      (create-notebook!
       :title "Bob NB"   :body-md "===prose===
b" :cells '() :author bob-dao)
      (with-mock-session (make-session :user alice)
        (let* ((res (notebooks-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Alice NB" body))
          (ng (search "Bob NB" body)))))))

;;; --- edit / update ---

(deftest edit-handler-404-for-missing
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((res (notebook-edit-handler
                    '((:id . "00000000-0000-0000-0000-000000000000")))))
          (ok (= 404 (response-status res))))))))

(deftest edit-handler-403-for-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (nb (create-notebook! :title "Owned"
                                       :body-md "===prose===
hi"
                                       :cells '()
                                       :author owner-dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user other)
        (let ((res (notebook-edit-handler (list (cons :id id)))))
          (ok (= 403 (response-status res))))))))

(deftest edit-handler-renders-form-for-owner
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "Mine"
                                       :body-md "===prose===
hi"
                                       :cells '()
                                       :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-edit-handler (list (cons :id id))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Edit Notebook" body))
          (ok (search "Mine" body)))))))

(deftest edit-handler-form-shows-existing-visibility
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook!
                :title "Public NB"
                :body-md "===prose===
hi"
                :cells '() :author dao
                :status "published" :visibility "public"
                :published-at (local-time:now)))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-edit-handler (list (cons :id id))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "name=visibility" body)
              "edit form has visibility select")
          ;; The public option must be marked selected for an existing public
          ;; notebook. The order of attributes is "value=public ... selected".
          (let* ((vis-pos (search "name=visibility" body))
                 (segment (and vis-pos (subseq body vis-pos
                                               (min (length body)
                                                    (+ vis-pos 400))))))
            (ok segment)
            (ok (search "value=public selected" segment)
                "the public option is marked selected")))))))

(deftest notebook-edit-form-embeds-cells-json
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook!
                :title "N" :slug "n"
                :body-md (format nil "===prose===~%hello~%~%===eval===~%(+ 1 2)")
                :cells nil :status "draft" :visibility "private" :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let ((body (first (response-body
                            (notebook-edit-handler (list (cons :id id)))))))
          (ok (search "data-cells=" body) "edit form embeds data-cells")
          (ok (search "code-eval" body) "cells JSON mentions eval kind"))))))

(deftest notebook-edit-form-loads-codemirror-and-editor-js
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "N" :slug "n"
                :body-md (format nil "===prose===~%hi")
                :cells nil :status "draft" :visibility "private" :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let ((body (first (response-body
                            (notebook-edit-handler (list (cons :id id)))))))
          (ok (search "codemirror" body) "loads CodeMirror importmap")
          (ok (search "/static/js/cell-editor.js" body) "loads cell-editor.js")
          (ok (search "cell-editor-root" body) "has editor mount point"))))))

(deftest update-handler-403-for-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (nb (create-notebook! :title "Owned"
                                       :body-md "===prose===
hi"
                                       :cells '()
                                       :author owner-dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user other)
        (let ((res (notebook-update-handler
                    (list (cons :id id)
                          (cons "title" "Stolen")
                          (cons "body" "===prose===
new")))))
          (ok (= 403 (response-status res))))))))

(deftest update-handler-persists-changes
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "Before"
                                       :body-md "===prose===
old"
                                       :cells '()
                                       :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-update-handler
                     (list (cons :id id)
                           (cons "title" "After")
                           (cons "body" "===prose===
new")
                           (cons "status" "published")))))
          (ok (= 302 (response-status res)))
          (ok (string= "/dashboard/notebooks" (response-location res)))
          (let ((updated (get-notebook-by-id id)))
            (ok (string= "After" (notebook-title updated)))
            (ok (search "new" (notebook-body-md updated)))
            (ok (string= "published" (notebook-status updated)))))))))

(deftest update-handler-shows-parser-errors
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "Before"
                                       :body-md "===prose===
ok"
                                       :cells '()
                                       :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-update-handler
                     (list (cons :id id)
                           (cons "title" "T")
                           (cons "body" "===banana===
nope"))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Validation errors" body))
          (let ((nb-after (get-notebook-by-id id)))
            (ok (string= "Before" (notebook-title nb-after)))))))))

(deftest update-handler-validation-error-preserves-cells-json
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "Before"
                                       :body-md "===prose===
old"
                                       :cells '()
                                       :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-update-handler
                     (list (cons :id id)
                           (cons "title" "")
                           (cons "body" "===prose===
hi

===eval===
(+ 1 2)"))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "data-cells=" body)
              "re-rendered form still embeds a data-cells attribute")
          (ok (search "code-eval" body)
              "submitted eval cell survives the validation re-render"))))))

(deftest update-handler-persists-visibility
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook!
                :title "Vis"
                :body-md "===prose===
hi"
                :cells '() :author dao
                :status "published" :visibility "private"
                :published-at (local-time:now)))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let ((res (notebook-update-handler
                    (list (cons :id id)
                          (cons "title" "Vis")
                          (cons "body" "===prose===
hi")
                          (cons "status" "published")
                          (cons "visibility" "public")))))
          (ok (= 302 (response-status res)))
          (let ((after (get-notebook-by-id id)))
            (ok (string= "public" (notebook-visibility after))
                "visibility flips from private to public")))))))

(deftest update-handler-preserves-cell-ids-on-rewrite
  (testing "rewriting unchanged body keeps stable cell ids in the JSONB cache"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (body "===prose===
Stable.

===eval===
(+ 1 2)")
             (cells-on-create
              (mapcar #'recurya/web/routes::cell->jsonb-form
                      (recurya/game/notebook-parser:parse-notebook-body body)))
             (nb (create-notebook!
                  :title "Stable" :body-md body
                  :cells cells-on-create :author dao))
             (id (princ-to-string (notebook-id nb)))
             (cells-before (recurya/db/notebooks:notebook-cells-parsed
                            (get-notebook-by-id id))))
        (with-mock-session (make-session :user user)
          (notebook-update-handler
           (list (cons :id id)
                 (cons "title" "Stable")
                 (cons "body" body))))
        (let ((cells-after
               (recurya/db/notebooks:notebook-cells-parsed
                (get-notebook-by-id id))))
          (ok (= (length cells-before) (length cells-after)))
          (ok (equalp cells-before cells-after)))))))

(deftest list-renders-3-state-pill-classes
  (testing "Notebooks listing emits status-{draft|private|public} CSS classes
that drive the 3-state pill colour, computed from (status, visibility)."
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id))))
        (create-notebook!
         :title "DraftA" :slug "drafta" :body-md "===prose===
hi"
         :cells '() :author dao :status "draft"
         :visibility "private")
        (create-notebook!
         :title "PrivPub" :slug "priv-pub-listing" :body-md "===prose===
hi"
         :cells '() :author dao :status "published"
         :visibility "private" :published-at (local-time:now))
        (create-notebook!
         :title "PublicPub" :slug "public-pub-listing" :body-md "===prose===
hi"
         :cells '() :author dao :status "published"
         :visibility "public" :published-at (local-time:now))
        (with-mock-session (make-session :user user)
          (let* ((res (notebooks-handler nil))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "status-draft" body)
                "draft notebook gets status-draft class")
            (ok (search "status-private" body)
                "published+private gets status-private class")
            (ok (search "status-public" body)
                "published+public gets status-public class")))))))

(deftest set-state-401-anonymous
  (with-mock-session (make-session)
    (let ((res (notebook-set-state-handler
                '((:id . "x") ("state" . "published-public")))))
      (ok (= 401 (response-status res))))))

(deftest set-state-403-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (nb (create-notebook!
                :title "Owned" :body-md "===prose===
hi"
                :cells '() :author owner-dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user other)
        (let ((res (notebook-set-state-handler
                    (list (cons :id id)
                          (cons "state" "published-public")))))
          (ok (= 403 (response-status res))))))))

(deftest set-state-decodes-published-public
  (testing "POST /dashboard/notebooks/:id/state with state=published-public sets
status=published, visibility=public, sets published_at, and returns the
full <details> dropdown markup (summary pill + 3 hx-post state buttons),
not a bare pill span."
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (nb (create-notebook!
                  :title "S" :body-md "===prose===
hi"
                  :cells '() :author dao
                  :status "draft" :visibility "private"))
             (id (princ-to-string (notebook-id nb))))
        (with-mock-session (make-session :user user)
          (let* ((res (notebook-set-state-handler
                       (list (cons :id id)
                             (cons "state" "published-public"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "status-public" body))
            ;; The dropdown markup must include the <details>/<summary>
            ;; wrapper and three hx-post buttons (one per state token),
            ;; otherwise repeated clicks will destroy the dropdown.
            (ok (search "<details" body))
            (ok (search "<summary" body))
            (ok (search "status-pill-menu" body))
            ;; spinneret HTML-escapes the inner double quotes of hx-vals.
            (ok (search "&quot;state&quot;:&quot;draft&quot;" body))
            (ok (search "&quot;state&quot;:&quot;published-private&quot;"
                        body))
            (ok (search "&quot;state&quot;:&quot;published-public&quot;"
                        body))
            (let ((after (get-notebook-by-id id)))
              (ok (string= "published" (notebook-status after)))
              (ok (string= "public" (notebook-visibility after)))
              (ok (recurya/db/notebooks:notebook-published-at
                   after)))))))))

(deftest set-state-decodes-draft-preserves-visibility
  (testing "state=draft from a published+public notebook turns it back to
draft while preserving published_at; the response body contains the full
<details> dropdown markup with the status-draft summary pill."
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (nb (create-notebook!
                  :title "S" :body-md "===prose===
hi"
                  :cells '() :author dao
                  :status "published" :visibility "public"
                  :published-at (local-time:now)))
             (id (princ-to-string (notebook-id nb))))
        (with-mock-session (make-session :user user)
          (let* ((res (notebook-set-state-handler
                       (list (cons :id id)
                             (cons "state" "draft"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "status-draft" body))
            (ok (search "<details" body))
            (ok (search "<summary" body))
            (let ((after (get-notebook-by-id id)))
              (ok (string= "draft" (notebook-status after))))))))))

(deftest set-state-rejects-invalid-state
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook!
                :title "S" :body-md "===prose===
hi"
                :cells '() :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let ((res (notebook-set-state-handler
                    (list (cons :id id)
                          (cons "state" "garbage")))))
          (ok (= 400 (response-status res))))))))

(deftest list-pill-renders-state-dropdown
  (testing "Each row renders a Draft/Private/Public dropdown that posts to
/dashboard/notebooks/:id/state."
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (nb (create-notebook!
                  :title "Rowable" :body-md "===prose===
hi"
                  :cells '() :author dao :status "draft"))
             (id (princ-to-string (notebook-id nb))))
        (with-mock-session (make-session :user user)
          (let* ((res (notebooks-handler nil))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search (format nil "/dashboard/notebooks/~A/state" id) body)
                "row links the new /state endpoint")
            (ok (search "published-public" body)
                "Public option is present in the dropdown")
            (ok (search "published-private" body)
                "Private option is present")))))))

(deftest confirm-delete-401-anonymous
  (with-mock-session (make-session)
    (let ((res (notebook-confirm-delete-handler '((:id . "x")))))
      (ok (= 401 (response-status res))))))

(deftest confirm-delete-404-missing
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((res (notebook-confirm-delete-handler
                    '((:id . "00000000-0000-0000-0000-000000000000")))))
          (ok (= 404 (response-status res))))))))

(deftest confirm-delete-403-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (nb (create-notebook! :title "Owned"
                                       :body-md "===prose===
hi"
                                       :cells '() :author owner-dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user other)
        (let ((res (notebook-confirm-delete-handler (list (cons :id id)))))
          (ok (= 403 (response-status res))))))))

(deftest confirm-delete-renders-modal-for-owner
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "Doomed"
                                       :body-md "===prose===
hi"
                                       :cells '() :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let* ((res (notebook-confirm-delete-handler (list (cons :id id))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "modal-overlay" body))
          (ok (search "Delete this notebook?" body))
          (ok (search (format nil "hx-post=\"/dashboard/notebooks/~A/delete\"" id) body))
          (ok (search "Delete notebook" body)))))))

(deftest delete-redirects-anonymous
  (with-mock-session (make-session)
    (let ((res (notebook-delete-handler '((:id . "x")))))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest delete-403-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (nb (create-notebook! :title "Owned"
                                       :body-md "===prose===
hi"
                                       :cells '() :author owner-dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user other)
        (with-mock-request (:htmx t)
          (let ((res (notebook-delete-handler (list (cons :id id)))))
            (ok (= 403 (response-status res)))))))))

(deftest delete-htmx-returns-oob-row
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "Bye"
                                       :body-md "===prose===
hi"
                                       :cells '() :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (with-mock-request (:htmx t)
          (let* ((res (notebook-delete-handler (list (cons :id id))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search (format nil "nb-row-~A" id) body))
            (ok (search "hx-swap-oob" body))
            (ok (null (get-notebook-by-id id)))))))))

(deftest delete-non-htmx-redirects
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "Bye"
                                       :body-md "===prose===
hi"
                                       :cells '() :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (with-mock-request (:htmx nil)
          (let ((res (notebook-delete-handler (list (cons :id id)))))
            (ok (= 302 (response-status res)))
            (ok (string= "/dashboard/notebooks" (response-location res)))))))))

(deftest public-list-shows-published-only
  (with-test-db
    (let* ((alice (mk-user))
           (alice-dao (get-user-by-id (getf alice :id)))
           (handle (users-handle alice-dao)))
      (create-notebook!
       :title "Pub" :slug "pub" :body-md "===prose===
hi"
       :cells '() :author alice-dao :status "published"
       :visibility "public" :published-at (local-time:now))
      (create-notebook!
       :title "Drafty" :slug "drafty" :body-md "===prose===
sh"
       :cells '() :author alice-dao :status "draft")
      (with-mock-session (make-session)
        (let* ((res (notebooks-public-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Pub" body))
          (ng (search "Drafty" body))
          (ok (search (format nil "/@~A/pub" handle) body)))))))

(deftest public-list-shows-only-public
  (with-test-db
    (let* ((alice (mk-user))
           (alice-dao (get-user-by-id (getf alice :id))))
      (create-notebook!
       :title "PubPublic" :slug "pub-public" :body-md "===prose===
hi"
       :cells '() :author alice-dao :status "published"
       :visibility "public" :published-at (local-time:now))
      (create-notebook!
       :title "PubPrivate" :slug "pub-private" :body-md "===prose===
shh"
       :cells '() :author alice-dao :status "published"
       :visibility "private" :published-at (local-time:now))
      (with-mock-session (make-session)
        (let* ((res (notebooks-public-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "PubPublic" body))
          (ng (search "PubPrivate" body)))))))

(deftest public-list-anonymous-200
  (with-test-db
    (with-mock-session (make-session)
      (let ((res (notebooks-public-handler nil)))
        (ok (= 200 (response-status res)))
        (ok (search "Notebooks" (first (response-body res))))))))

(deftest public-page-owner-can-preview-draft
  (with-test-db
    (let* ((owner (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (handle (users-handle owner-dao)))
      (create-notebook!
       :title "Owner Draft" :slug "od" :body-md "===prose===
mine"
       :cells '() :author owner-dao :status "draft")
      (with-mock-session (make-session :user owner)
        (let* ((res (public-notebook-by-handle-handler
                     (list (cons :captures (list handle "od")))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Owner Draft" body)))))))

(deftest public-page-published-anonymous
  (with-test-db
    (let* ((owner (mk-user))
           (dao (get-user-by-id (getf owner :id)))
           (handle (users-handle dao)))
      (create-notebook!
       :title "Open" :slug "open" :body-md "===prose===
hello"
       :cells '() :author dao :status "published"
       :visibility "public" :published-at (local-time:now))
      (with-mock-session (make-session)
        (let ((res (public-notebook-by-handle-handler
                    (list (cons :captures (list handle "open"))))))
          (ok (= 200 (response-status res))))))))

(deftest public-page-published-private-404-for-others
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (handle (users-handle owner-dao)))
      (create-notebook!
       :title "Private Pub" :slug "priv-pub" :body-md "===prose===
shh"
       :cells '() :author owner-dao :status "published"
       :visibility "private" :published-at (local-time:now))
      (with-mock-session (make-session :user other)
        (let ((res (public-notebook-by-handle-handler
                    (list (cons :captures (list handle "priv-pub"))))))
          (ok (= 404 (response-status res)))))
      (with-mock-session (make-session)
        (let ((res (public-notebook-by-handle-handler
                    (list (cons :captures (list handle "priv-pub"))))))
          (ok (= 404 (response-status res))))))))

(deftest public-page-published-private-200-for-owner
  (with-test-db
    (let* ((owner (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (handle (users-handle owner-dao)))
      (create-notebook!
       :title "Owner Private Pub" :slug "owner-priv-pub" :body-md "===prose===
mine"
       :cells '() :author owner-dao :status "published"
       :visibility "private" :published-at (local-time:now))
      (with-mock-session (make-session :user owner)
        (let* ((res (public-notebook-by-handle-handler
                     (list (cons :captures
                                 (list handle "owner-priv-pub")))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Owner Private Pub" body)))))))

(deftest run-cell-published-private-404-for-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (dao (get-user-by-id (getf owner :id)))
           (handle (users-handle dao))
           (body "===prose===
hi

===eval===
(+ 1 2)")
           (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                          (recurya/game/notebook-parser:parse-notebook-body body))))
      (create-notebook!
       :title "PrivPub" :slug "priv-pub-run" :body-md body
       :cells cells :author dao :status "published"
       :visibility "private" :published-at (local-time:now))
      (with-mock-session (make-session :user other)
        (let ((res (public-notebook-cell-run-by-handle-handler
                    `((:captures . (,handle "priv-pub-run" "1"))
                      ("codes[]" . "")
                      ("codes[]" . "(+ 1 2)")))))
          (ok (= 404 (response-status res))))))))

(deftest public-page-renders-code-cell-with-correct-run-url
  (testing "code cells use /@<handle>/<slug>/cells/<i>/run"
    (with-test-db
      (let* ((owner (mk-user))
             (dao (get-user-by-id (getf owner :id)))
             (handle (recurya/db/users:users-handle dao))
             (body "===prose===
hi

===eval===
(+ 1 2)")
             (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                            (recurya/game/notebook-parser:parse-notebook-body body))))
        (create-notebook!
         :title "Code" :slug "with-code" :body-md body
         :cells cells :author dao :status "published"
         :visibility "public" :published-at (local-time:now))
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       (list (cons :captures (list handle "with-code")))))
                 (html (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "data-cell-id=" html))
            (ok (search (format nil "hx-post=\"/@~A/with-code/cells/1/run\""
                                handle)
                        html))
            (ng (search "/wardlisp/learn/" html))))))))

(deftest public-page-renders-prose-markdown-not-literal
  (testing "prose body markdown is rendered to sanitized HTML, not escaped verbatim"
    (with-test-db
      (let* ((owner (mk-user))
             (dao (get-user-by-id (getf owner :id)))
             (handle (users-handle dao))
             (body "===prose===
**bold** *italic* hello.")
             (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                            (recurya/game/notebook-parser:parse-notebook-body body))))
        (create-notebook!
         :title "Prose" :slug "prose-md" :body-md body
         :cells cells :author dao :status "published"
         :visibility "public" :published-at (local-time:now))
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       (list (cons :captures (list handle "prose-md")))))
                 (html (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "<strong>bold</strong>" html))
            (ng (search "**bold**" html))))))))

(deftest public-page-renders-200-when-body-has-solution-cells
  (testing "viewer survives notebooks that contain ===solution=== cells; a
non-gated solution's body is shown in a collapsible details element"
    (with-test-db
      (let* ((owner (mk-user))
             (dao (get-user-by-id (getf owner :id)))
             (handle (users-handle dao))
             (body "===exercise: square===
(define (square x) ???)

===expect: square===
4

===solution: square===
(define (square x) (* x x))")
             (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                            (recurya/game/notebook-parser:parse-notebook-body body))))
        (create-notebook!
         :title "Solo" :slug "with-solution" :body-md body
         :cells cells :author dao :status "published"
         :visibility "public" :published-at (local-time:now))
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       (list (cons :captures
                                   (list handle "with-solution")))))
                 (html (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "(* x x)" html)
                "non-gated solution body IS shown to public viewers")))))))

(deftest solution-gated-hidden-until-passed
  (testing "a gated (===solution-locked===) solution body is absent from the
reader page until the preceding exercise is passed; a non-gated
(===solution===) solution is always shown"
    (with-test-db
      (let* ((owner (mk-user))
             (dao (get-user-by-id (getf owner :id)))
             (handle (users-handle dao))
             (body (format nil "===exercise: q===~%; ?~%~%===expect===~%1~%~%===solution-locked: ans===~%(SECRET-ANSWER)~%~%===solution: open===~%(OPEN-ANSWER)"))
             (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                            (recurya/game/notebook-parser:parse-notebook-body body))))
        (create-notebook!
         :title "N" :slug "n" :body-md body
         :cells cells :author dao :status "published"
         :visibility "public" :published-at (local-time:now))
        (with-mock-session (make-session)
          (let ((page (first (response-body
                              (public-notebook-by-handle-handler
                               (list (cons :captures (list handle "n"))))))))
            (ng (search "SECRET-ANSWER" page)
                "gated solution body is NOT in the HTML when not passed")
            (ok (search "OPEN-ANSWER" page)
                "non-gated solution body IS shown")))))))

(deftest exercise-pass-oob-reveals-gated-solution
  (testing "passing an exercise reveals the following gated solution via OOB swap"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (handle (users-handle dao))
             (body (format nil "===exercise: q===~%; fill~%~%===expect===~%3~%~%===solution-locked: ans===~%(SECRET-ANSWER)"))
             (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                            (recurya/game/notebook-parser:parse-notebook-body body))))
        (create-notebook!
         :title "N" :slug "n" :body-md body
         :cells cells :author dao :status "published"
         :visibility "public" :published-at (local-time:now))
        (with-mock-session (make-session :user user)
          (let* ((res (public-notebook-cell-run-by-handle-handler
                       `((:captures . (,handle "n" "0"))
                         ("codes[]" . "3"))))
                 (frag (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "hx-swap-oob" frag) "response carries an OOB swap")
            (ok (search "cell-1-solution" frag)
                "targets the gated solution container")
            (ok (search "SECRET-ANSWER" frag)
                "reveals the solution body on pass")
            (ng (search "notebook-code" frag)
                "OOB reveal must not inject an extra codes[] input")))))))

(deftest run-cell-404-missing-slug
  (with-test-db
    (let* ((owner (mk-user))
           (dao (get-user-by-id (getf owner :id)))
           (handle (users-handle dao)))
      (with-mock-session (make-session)
        (let ((res (public-notebook-cell-run-by-handle-handler
                    `((:captures . (,handle "no-such" "0"))))))
          (ok (= 404 (response-status res))))))))

(deftest run-cell-rejects-prose-cell
  (with-test-db
    (let* ((owner (mk-user))
           (dao (get-user-by-id (getf owner :id)))
           (handle (users-handle dao))
           (body "===prose===
hi")
           (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                          (recurya/game/notebook-parser:parse-notebook-body body))))
      (create-notebook!
       :title "P" :slug "p1" :body-md body
       :cells cells :author dao :status "published"
       :visibility "public" :published-at (local-time:now))
      (with-mock-session (make-session)
        (let ((res (public-notebook-cell-run-by-handle-handler
                    `((:captures . (,handle "p1" "0"))))))
          (ok (= 400 (response-status res))))))))

(deftest run-cell-eval-anonymous-no-persist
  (with-test-db
    (let* ((owner (mk-user))
           (dao (get-user-by-id (getf owner :id)))
           (handle (users-handle dao))
           (body "===prose===
hi

===eval===
(+ 1 2)")
           (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                          (recurya/game/notebook-parser:parse-notebook-body body))))
      (create-notebook!
       :title "Eval" :slug "ev" :body-md body
       :cells cells :author dao :status "published"
       :visibility "public" :published-at (local-time:now))
      (with-mock-session (make-session)
        (let* ((res (public-notebook-cell-run-by-handle-handler
                     `((:captures . (,handle "ev" "1"))
                       ("codes[]" . "")
                       ("codes[]" . "(+ 1 2)")))))
          (ok (= 200 (response-status res))))))))

(deftest run-cell-eval-logged-in-persists-saved-code
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (dao (get-user-by-id (getf owner :id)))
           (handle (users-handle dao))
           (body "===prose===
hi

===eval===
(+ 1 2)")
           (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                          (recurya/game/notebook-parser:parse-notebook-body body)))
           (nb (create-notebook!
                :title "Pers" :slug "pers" :body-md body
                :cells cells :author dao :status "published"
                :visibility "public" :published-at (local-time:now)))
           (nb-uuid (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user other)
        (let ((res (public-notebook-cell-run-by-handle-handler
                    `((:captures . (,handle "pers" "1"))
                      ("codes[]" . "")
                      ("codes[]" . "(+ 1 2)")))))
          (ok (= 200 (response-status res))))
        (let ((codes (recurya/db/learn:user-cell-codes
                      (getf other :id) nb-uuid)))
          (ok (= 1 (length codes)))
          (ok (search "(+ 1 2)" (cdar codes))))))))

(deftest notebook-page-with-course-shows-sidebar
  (testing "?course=<slug> renders the course sidebar with course title link
and the breadcrumb shows Notebooks > Course Title > Notebook Title."
    (with-test-db
      (let* ((author (mk-user))
             (dao (get-user-by-id (getf author :id)))
             (handle (users-handle dao))
             (course (create-course! :title "SICP"
                                     :slug "sicp"
                                     :status "published"
                                     :visibility "public"
                                     :published-at (local-time:now)
                                     :author dao))
             (nb (create-notebook!
                  :title "1.1.1 Expressions"
                  :slug "sicp-1-1-1"
                  :body-md "===prose===
hi"
                  :cells nil
                  :status "published"
                  :visibility "public"
                  :published-at (local-time:now)
                  :author dao)))
        (add-notebook-to-course! (course-id course) (notebook-id nb)
                                 :position 0)
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       `((:captures . (,handle "sicp-1-1-1"))
                         ("course" . "sicp"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search (format nil "href=\"/c/@~A/sicp\"" handle) body))
            (ok (search "SICP" body))
            (ok (search "href=\"/notebooks\"" body))
            (ok (search "1.1.1 Expressions" body))))))))

(deftest notebook-page-with-course-shows-prev-next
  (testing "middle notebook in course gets prev=first, next=last URLs
preserving the ?course=<slug> query string."
    (with-test-db
      (let* ((author (mk-user))
             (dao (get-user-by-id (getf author :id)))
             (handle (users-handle dao))
             (course (create-course! :title "SICP"
                                     :slug "sicp"
                                     :status "published"
                                     :visibility "public"
                                     :published-at (local-time:now)
                                     :author dao))
             (nb1 (create-notebook!
                   :title "First" :slug "first"
                   :body-md "===prose===
a"
                   :cells nil :status "published"
                   :visibility "public"
                   :published-at (local-time:now) :author dao))
             (nb2 (create-notebook!
                   :title "Middle" :slug "middle"
                   :body-md "===prose===
b"
                   :cells nil :status "published"
                   :visibility "public"
                   :published-at (local-time:now) :author dao))
             (nb3 (create-notebook!
                   :title "Last" :slug "last"
                   :body-md "===prose===
c"
                   :cells nil :status "published"
                   :visibility "public"
                   :published-at (local-time:now) :author dao)))
        (add-notebook-to-course! (course-id course) (notebook-id nb1)
                                 :position 0)
        (add-notebook-to-course! (course-id course) (notebook-id nb2)
                                 :position 1)
        (add-notebook-to-course! (course-id course) (notebook-id nb3)
                                 :position 2)
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       `((:captures . (,handle "middle"))
                         ("course" . "sicp"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search (format nil "/@~A/first?course=sicp" handle) body))
            (ok (search (format nil "/@~A/last?course=sicp" handle)
                        body))))))))

(deftest notebook-page-with-course-no-prev-at-first
  (testing "first notebook in course renders next URL but no prev URL."
    (with-test-db
      (let* ((author (mk-user))
             (dao (get-user-by-id (getf author :id)))
             (handle (users-handle dao))
             (course (create-course! :title "SICP"
                                     :slug "sicp"
                                     :status "published"
                                     :visibility "public"
                                     :published-at (local-time:now)
                                     :author dao))
             (nb1 (create-notebook!
                   :title "First" :slug "first"
                   :body-md "===prose===
a"
                   :cells nil :status "published"
                   :visibility "public"
                   :published-at (local-time:now) :author dao))
             (nb2 (create-notebook!
                   :title "Second" :slug "second"
                   :body-md "===prose===
b"
                   :cells nil :status "published"
                   :visibility "public"
                   :published-at (local-time:now) :author dao)))
        (add-notebook-to-course! (course-id course) (notebook-id nb1)
                                 :position 0)
        (add-notebook-to-course! (course-id course) (notebook-id nb2)
                                 :position 1)
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       `((:captures . (,handle "first"))
                         ("course" . "sicp"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search (format nil "/@~A/second?course=sicp" handle)
                        body))
            (ng (search (format nil "/@~A/first?course=sicp" handle)
                        body)
                "the current page does not link to itself as prev")))))))

(deftest notebook-page-with-course-no-next-at-last
  (testing "last notebook in course renders prev URL but no next URL."
    (with-test-db
      (let* ((author (mk-user))
             (dao (get-user-by-id (getf author :id)))
             (handle (users-handle dao))
             (course (create-course! :title "SICP"
                                     :slug "sicp"
                                     :status "published"
                                     :visibility "public"
                                     :published-at (local-time:now)
                                     :author dao))
             (nb1 (create-notebook!
                   :title "First" :slug "first"
                   :body-md "===prose===
a"
                   :cells nil :status "published"
                   :visibility "public"
                   :published-at (local-time:now) :author dao))
             (nb2 (create-notebook!
                   :title "Second" :slug "second"
                   :body-md "===prose===
b"
                   :cells nil :status "published"
                   :visibility "public"
                   :published-at (local-time:now) :author dao)))
        (add-notebook-to-course! (course-id course) (notebook-id nb1)
                                 :position 0)
        (add-notebook-to-course! (course-id course) (notebook-id nb2)
                                 :position 1)
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       `((:captures . (,handle "second"))
                         ("course" . "sicp"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search (format nil "/@~A/first?course=sicp" handle)
                        body))
            (ng (search (format nil "/@~A/second?course=sicp" handle)
                        body)
                "the current page does not link to itself as next")))))))

(deftest notebook-page-with-invalid-course-falls-back-no-context
  (testing "?course=<unknown-slug> falls back to no-course-context render
(no sidebar header link, no prev/next URLs, default breadcrumb logic)."
    (with-test-db
      (let* ((author (mk-user))
             (dao (get-user-by-id (getf author :id)))
             (handle (users-handle dao))
             (nb (create-notebook!
                  :title "Standalone" :slug "standalone"
                  :body-md "===prose===
hi"
                  :cells nil :status "published"
                  :visibility "public"
                  :published-at (local-time:now) :author dao)))
        (declare (ignore nb))
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       `((:captures . (,handle "standalone"))
                         ("course" . "no-such-course"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ng (search "/c/no-such-course" body)
                "no legacy-shaped link to a non-existent course")
            (ng (search (format nil "/c/@~A/no-such-course" handle) body)
                "no handle-scoped link to a non-existent course")
            (ng (search "?course=no-such-course" body)
                "no prev/next URLs referencing the unknown course")
            (ok (search "Standalone" body))))))))

(deftest notebook-page-with-private-course-hides-sidebar
  (testing "?course=<slug> for a published-but-PRIVATE course is ignored for
anonymous viewers: the public notebook still renders, but the private
course's title, sidebar link and prev/next URLs never leak. Regression
guard for the can-view-course-p gate on the ?course= sidebar context."
    (with-test-db
      (let* ((author (mk-user))
             (dao (get-user-by-id (getf author :id)))
             (handle (users-handle dao))
             (course (create-course! :title "Secret Syllabus"
                                     :slug "secret"
                                     :status "published"
                                     :visibility "private"
                                     :published-at (local-time:now)
                                     :author dao))
             (nb (create-notebook!
                  :title "Public Lesson"
                  :slug "public-lesson"
                  :body-md "===prose===
hi"
                  :cells nil
                  :status "published"
                  :visibility "public"
                  :published-at (local-time:now)
                  :author dao)))
        (add-notebook-to-course! (course-id course) (notebook-id nb)
                                 :position 0)
        (with-mock-session (make-session)
          (let* ((res (public-notebook-by-handle-handler
                       `((:captures . (,handle "public-lesson"))
                         ("course" . "secret"))))
                 (body (first (response-body res))))
            ;; The public notebook itself still renders.
            (ok (= 200 (response-status res)))
            (ok (search "Public Lesson" body))
            ;; The private course context must NOT leak to an anonymous viewer.
            (ng (search "Secret Syllabus" body)
                "private course title must not appear in sidebar/breadcrumb")
            (ng (search (format nil "/c/@~A/secret" handle) body)
                "no link to the private course page")
            (ng (search "?course=secret" body)
                "no prev/next URLs scoped to the private course")))))))

(deftest by-handle-different-authors-same-slug-isolated
  (testing "GET /@:handle/:slug returns each author's notebook when both
authors use the same slug"
    (with-test-db
      (let* ((alice-dao (create-test-user :email-prefix "alice"
                                          :handle "alice-7b"))
             (bob-dao (create-test-user :email-prefix "bob"
                                        :handle "bob-7b")))
        (create-notebook! :title "Alice intro" :slug "intro"
                          :body-md "===prose===
alice"
                          :cells nil :author alice-dao
                          :status "published" :visibility "public"
                          :published-at (local-time:now))
        (create-notebook! :title "Bob intro" :slug "intro"
                          :body-md "===prose===
bob"
                          :cells nil :author bob-dao
                          :status "published" :visibility "public"
                          :published-at (local-time:now))
        (with-mock-session (make-session)
          (let* ((res-alice
                  (public-notebook-by-handle-handler
                   '((:captures . ("alice-7b" "intro")))))
                 (res-bob
                  (public-notebook-by-handle-handler
                   '((:captures . ("bob-7b" "intro"))))))
            (ok (= 200 (response-status res-alice)))
            (ok (= 200 (response-status res-bob)))
            (ok (search "Alice intro" (first (response-body res-alice))))
            (ng (search "Bob intro" (first (response-body res-alice))))
            (ok (search "Bob intro" (first (response-body res-bob))))
            (ng (search "Alice intro" (first (response-body res-bob))))))))))

(deftest by-handle-404-unknown-handle
  (with-test-db
    (with-mock-session (make-session)
      (let ((res (public-notebook-by-handle-handler
                  '((:captures . ("ghost-7b" "intro"))))))
        (ok (= 404 (response-status res)))))))

(deftest by-handle-404-draft-anonymous
  (with-test-db
    (let ((dao (create-test-user :email-prefix "draftee"
                                 :handle "draftee-7b")))
      (create-notebook! :title "Hidden" :slug "hidden"
                        :body-md "===prose===
shh"
                        :cells nil :author dao
                        :status "draft")
      (with-mock-session (make-session)
        (let ((res (public-notebook-by-handle-handler
                    '((:captures . ("draftee-7b" "hidden"))))))
          (ok (= 404 (response-status res))))))))

(deftest by-handle-cell-run-200-eval
  (testing "POST /@:handle/:slug/cells/:i/run executes a cell"
    (with-test-db
      (let* ((dao (create-test-user :email-prefix "runner"
                                    :handle "runner-7b"))
             (body "===prose===
hi

===eval===
(+ 1 2)")
             (cells (mapcar #'recurya/web/routes::cell->jsonb-form
                            (recurya/game/notebook-parser:parse-notebook-body
                             body))))
        (create-notebook! :title "Run" :slug "run-nb" :body-md body
                          :cells cells :author dao
                          :status "published" :visibility "public"
                          :published-at (local-time:now))
        (with-mock-session (make-session)
          (let ((res (public-notebook-cell-run-by-handle-handler
                      `((:captures . ("runner-7b" "run-nb" "1"))
                        ("codes[]" . "")
                        ("codes[]" . "(+ 1 2)")))))
            (ok (= 200 (response-status res)))))))))

(deftest by-handle-cell-run-404-unknown-handle
  (with-test-db
    (with-mock-session (make-session)
      (let ((res (public-notebook-cell-run-by-handle-handler
                  '((:captures . ("ghost-7b" "x" "0"))))))
        (ok (= 404 (response-status res)))))))

(deftest decode-state-token-published-unlisted
  (testing "%decode-state-token maps published-unlisted to (published, unlisted)"
    (multiple-value-bind (status vis)
        (recurya/web/routes::%decode-state-token "published-unlisted")
      (ok (string= status "published"))
      (ok (string= vis "unlisted")))))

(deftest create-handler-persists-visibility-unlisted
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((params '(("title" . "Unlisted NB")
                        ("slug" . "")
                        ("summary" . "")
                        ("body" . "===prose===
hi")
                        ("status" . "published")
                        ("visibility" . "unlisted"))))
          (notebook-create-handler params)
          (let ((nb (get-notebook-by-slug "unlisted-nb")))
            (ok nb)
            (ok (string= "unlisted" (notebook-visibility nb)))))))))

(deftest notebook-set-state-published-unlisted
  (testing "set-state published-unlisted persists unlisted and returns the
4-state dropdown with an Unlisted summary pill"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (nb (create-notebook!
                  :title "S" :body-md "===prose===
hi"
                  :cells '() :author dao
                  :status "draft" :visibility "private"))
             (id (princ-to-string (notebook-id nb))))
        (with-mock-session (make-session :user user)
          (let* ((res (notebook-set-state-handler
                       (list (cons :id id)
                             (cons "state" "published-unlisted"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "status-unlisted" body))
            (ok (search "&quot;state&quot;:&quot;published-unlisted&quot;" body))
            (let ((after (get-notebook-by-id id)))
              (ok (string= "published" (notebook-status after)))
              (ok (string= "unlisted" (notebook-visibility after))))))))))

(deftest dashboard-shows-copy-link-for-unlisted-only
  (testing "an unlisted notebook row exposes a copy-link affordance; a public
notebook row does not"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id))))
        (create-notebook!
         :title "UnlistedRow" :slug "unlisted-row" :body-md "===prose===
hi"
         :cells '() :author dao :status "published" :visibility "unlisted"
         :published-at (local-time:now))
        (with-mock-session (make-session :user user)
          (let ((body (first (response-body (notebooks-handler nil)))))
            (ok (search "copy-link-btn" body)
                "unlisted row has a copy-link button")
            (ok (search "data-share-url" body)
                "copy button carries data-share-url (distinct from the title href)")
            (ok (search (format nil "/@~A/unlisted-row" (getf user :handle))
                        body)
                "share URL targets the notebook")))))))

(deftest unlisted-notebook-page-has-noindex
  (testing "an unlisted notebook page carries robots=noindex; a public one
does not"
    (with-test-db
      (let* ((dao (create-test-user :email-prefix "ix" :handle "ix-7b"))
             (handle (users-handle dao)))
        (create-notebook! :title "U" :slug "u-nb" :body-md "===prose===
hi"
                          :cells nil :author dao
                          :status "published" :visibility "unlisted"
                          :published-at (local-time:now))
        (create-notebook! :title "P" :slug "p-nb" :body-md "===prose===
hi"
                          :cells nil :author dao
                          :status "published" :visibility "public"
                          :published-at (local-time:now))
        (with-mock-session (make-session)
          (let ((u-body (first (response-body
                                (public-notebook-by-handle-handler
                                 `((:captures . (,handle "u-nb")))))))
                (p-body (first (response-body
                                (public-notebook-by-handle-handler
                                 `((:captures . (,handle "p-nb"))))))))
            (ok (search "noindex" u-body) "unlisted page is noindex")
            (ng (search "noindex" p-body) "public page is indexable")))))))

(deftest unlisted-notebook-absent-from-public-listing-and-profile
  (testing "an unlisted notebook appears on neither /notebooks nor /@handle"
    (with-test-db
      (let* ((dao (create-test-user :email-prefix "hid" :handle "hid-7b"))
             (handle (users-handle dao)))
        (create-notebook! :title "HiddenList" :slug "hidden-list"
                          :body-md "===prose===
hi"
                          :cells nil :author dao
                          :status "published" :visibility "unlisted"
                          :published-at (local-time:now))
        (with-mock-session (make-session)
          (let ((listing (first (response-body (notebooks-public-handler nil))))
                (profile (first (response-body
                                 (profile-handler
                                  `((:captures . (,handle))))))))
            (ng (search "HiddenList" listing) "not in /notebooks")
            (ng (search "HiddenList" profile) "not on /@handle profile")))))))
