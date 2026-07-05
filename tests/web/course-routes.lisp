;;;; tests/web/course-routes.lisp --- Tests for course route handlers.

(defpackage #:recurya/tests/web/course-routes
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db
                #:create-test-user)
  (:import-from #:recurya/web/routes
                #:courses-me-handler
                #:course-new-handler
                #:course-create-handler
                #:course-edit-handler
                #:course-update-handler
                #:course-set-state-handler
                #:course-confirm-delete-handler
                #:course-delete-handler
                #:course-add-notebook-handler
                #:course-notebook-move-up-handler
                #:course-notebook-move-down-handler
                #:course-notebook-remove-handler
                #:public-course-by-handle-handler
                #:courses-public-handler)
  (:import-from #:recurya/db/notebooks
                #:create-notebook!
                #:notebook-id)
  (:import-from #:recurya/db/course-notebooks
                #:add-notebook-to-course!
                #:list-course-notebooks
                #:course-notebook-id
                #:course-notebook-position)
  (:import-from #:recurya/db/users
                #:get-user-by-id
                #:users-id
                #:users-handle
                #:users-display-name)
  (:import-from #:recurya/db/courses
                #:create-course!
                #:get-course-by-id
                #:get-course-by-slug
                #:course-id
                #:course-title
                #:course-slug
                #:course-status
                #:course-visibility
                #:course-published-at)
  (:import-from #:uuid
                #:make-v4-uuid))

(in-package #:recurya/tests/web/course-routes)

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
                       (when ,htmx
                         (list :http-hx-request "true"))))
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
  (let ((dao (create-test-user :email-prefix "course-route")))
    (list :id (users-id dao)
          :email (format nil "course-route-~A@example.com" (make-v4-uuid))
          :name (users-display-name dao)
          :handle (users-handle dao)
          :role :user
          :provider "google"
          :timezone "UTC"
          :language "en")))

;;; --- list ---

(deftest course-list-handler-redirects-anonymous
  (with-mock-session (make-session)
    (let ((res (courses-me-handler nil)))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest course-list-handler-shows-own-only
  (with-test-db
    (let* ((alice (mk-user))
           (bob   (mk-user))
           (alice-dao (get-user-by-id (getf alice :id)))
           (bob-dao   (get-user-by-id (getf bob :id))))
      (create-course! :title "Alice C" :author alice-dao)
      (create-course! :title "Bob C"   :author bob-dao)
      (with-mock-session (make-session :user alice)
        (let* ((res (courses-me-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Alice C" body))
          (ng (search "Bob C" body)))))))

;;; --- new ---

(deftest course-new-handler-redirects-anonymous
  (with-mock-session (make-session)
    (let ((res (course-new-handler nil)))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest course-new-handler-renders-form-for-user
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((res (course-new-handler nil)))
          (ok (= 200 (response-status res)))
          (ok (search "New Course" (first (response-body res)))))))))

;;; --- create ---

(deftest course-create-handler-redirects-anonymous
  (with-mock-session (make-session)
    (let ((res (course-create-handler '(("title" . "x")))))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest course-create-handler-rejects-blank-title
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((res (course-create-handler
                     '(("title" . "") ("summary" . "s"))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Title is required" body)))))))

(deftest course-create-handler-persists-and-redirects
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((params '(("title" . "My Course")
                         ("slug" . "")
                         ("summary" . "Hello")
                         ("status" . "draft")))
               (res (course-create-handler params)))
          (ok (= 302 (response-status res)))
          (ok (string= "/dashboard/courses" (response-location res)))
          (let ((c (get-course-by-slug "my-course")))
            (ok c)
            (ok (string= "My Course" (course-title c)))
            (ok (string= "draft" (course-status c)))))))))

(deftest course-create-handler-published-sets-published-at
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((params '(("title" . "Pub Course")
                        ("slug" . "")
                        ("summary" . "")
                        ("status" . "published"))))
          (course-create-handler params)
          (let ((c (get-course-by-slug "pub-course")))
            (ok c)
            (ok (string= "published" (course-status c)))
            (ok (course-published-at c))))))))

(deftest course-new-handler-form-has-visibility-select
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let* ((res (course-new-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "name=visibility" body))
          (ok (search "value=private" body))
          (ok (search "value=public" body)))))))

(deftest course-create-handler-persists-visibility-public
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((params '(("title" . "Vis Course")
                        ("slug" . "")
                        ("summary" . "")
                        ("status" . "published")
                        ("visibility" . "public"))))
          (course-create-handler params)
          (let ((c (get-course-by-slug "vis-course")))
            (ok c)
            (ok (string= "public" (course-visibility c)))))))))

(deftest course-create-handler-defaults-visibility-private
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((params '(("title" . "Default Priv C")
                        ("slug" . "")
                        ("summary" . "")
                        ("status" . "draft"))))
          (course-create-handler params)
          (let ((c (get-course-by-slug "default-priv-c")))
            (ok c)
            (ok (string= "private" (course-visibility c)))))))))

;;; --- edit ---

(deftest course-edit-handler-404-for-missing
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((res (course-edit-handler
                    '((:id . "00000000-0000-0000-0000-000000000000")))))
          (ok (= 404 (response-status res))))))))

(deftest course-edit-handler-403-for-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (c (create-course! :title "Owned" :author owner-dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user other)
        (let ((res (course-edit-handler (list (cons :id id)))))
          (ok (= 403 (response-status res))))))))

(deftest course-edit-handler-renders-form-for-owner
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Mine" :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (let* ((res (course-edit-handler (list (cons :id id))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Edit Course" body))
          (ok (search "Mine" body)))))))

(deftest course-edit-handler-form-shows-existing-visibility
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Public C"
                              :status "published"
                              :visibility "public"
                              :published-at (local-time:now)
                              :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (let* ((res (course-edit-handler (list (cons :id id))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "name=visibility" body))
          (let* ((vis-pos (search "name=visibility" body))
                 (segment (and vis-pos (subseq body vis-pos
                                               (min (length body)
                                                    (+ vis-pos 400))))))
            (ok segment)
            (ok (search "value=public selected" segment))))))))

(deftest course-edit-handler-eligible-list-includes-published-any-visibility
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Mine" :author dao))
           (id (princ-to-string (course-id c))))
      ;; Any of the owner's PUBLISHED notebooks are eligible regardless of
      ;; visibility (public or private/unlisted)...
      (create-notebook! :title "EligPub" :body-md (format nil "===prose===~%hi")
        :cells nil :status "published" :visibility "public"
        :published-at (local-time:now) :author dao)
      (create-notebook! :title "EligPriv" :body-md (format nil "===prose===~%shh")
        :cells nil :status "published" :visibility "private"
        :published-at (local-time:now) :author dao)
      ;; ...but a DRAFT notebook is still excluded.
      (create-notebook! :title "EligDraft" :body-md (format nil "===prose===~%wip")
        :cells nil :status "draft" :visibility "public" :author dao)
      (with-mock-session (make-session :user user)
        (let* ((res (course-edit-handler (list (cons :id id))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "EligPub" body)
              "published+public notebook is eligible")
          (ok (search "EligPriv" body)
              "published+private notebook is now eligible too")
          (ng (search "EligDraft" body)
              "a draft notebook is still excluded"))))))

;;; --- update ---

(deftest course-update-handler-403-for-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (c (create-course! :title "Owned" :author owner-dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user other)
        (let ((res (course-update-handler
                    (list (cons :id id)
                          (cons "title" "Stolen")))))
          (ok (= 403 (response-status res))))))))

(deftest course-update-handler-persists-changes
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Before" :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (let ((res (course-update-handler
                    (list (cons :id id)
                          (cons "title" "After")
                          (cons "summary" "now")
                          (cons "status" "published")))))
          (ok (= 302 (response-status res)))
          (ok (string= "/dashboard/courses" (response-location res)))
          (let ((updated (get-course-by-id id)))
            (ok (string= "After" (course-title updated)))
            (ok (string= "published" (course-status updated)))
            (ok (course-published-at updated))))))))

(deftest course-update-handler-persists-visibility
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Vis"
                              :status "published"
                              :visibility "private"
                              :published-at (local-time:now)
                              :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (let ((res (course-update-handler
                    (list (cons :id id)
                          (cons "title" "Vis")
                          (cons "status" "published")
                          (cons "visibility" "public")))))
          (ok (= 302 (response-status res)))
          (let ((after (get-course-by-id id)))
            (ok (string= "public" (course-visibility after)))))))))

(deftest course-list-renders-3-state-pill-classes
  (testing "Courses listing emits status-{draft|private|public} CSS classes."
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id))))
        (create-course! :title "DraftC" :status "draft"
                        :visibility "private" :author dao)
        (create-course! :title "PrivPubC" :status "published"
                        :visibility "private"
                        :published-at (local-time:now) :author dao)
        (create-course! :title "PublicPubC" :status "published"
                        :visibility "public"
                        :published-at (local-time:now) :author dao)
        (with-mock-session (make-session :user user)
          (let* ((res (courses-me-handler nil))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "status-draft" body))
            (ok (search "status-private" body))
            (ok (search "status-public" body))))))))

(deftest course-set-state-401-anonymous
  (with-mock-session (make-session)
    (let ((res (course-set-state-handler
                '((:id . "x") ("state" . "published-public")))))
      (ok (= 401 (response-status res))))))

(deftest course-set-state-403-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (c (create-course! :title "Owned" :author owner-dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user other)
        (let ((res (course-set-state-handler
                    (list (cons :id id)
                          (cons "state" "published-public")))))
          (ok (= 403 (response-status res))))))))

(deftest course-set-state-decodes-published-public
  (testing "POST /dashboard/courses/:id/state with state=published-public sets
status=published, visibility=public, sets published_at, and returns the
full <details> dropdown markup (summary pill + 3 hx-post state buttons),
not a bare pill span."
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (c (create-course! :title "S" :author dao
                                :status "draft" :visibility "private"))
             (id (princ-to-string (course-id c))))
        (with-mock-session (make-session :user user)
          (let* ((res (course-set-state-handler
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
            (let ((after (get-course-by-id id)))
              (ok (string= "published" (course-status after)))
              (ok (string= "public" (course-visibility after)))
              (ok (course-published-at after)))))))))

(deftest course-set-state-rejects-invalid-state
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "S" :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (let ((res (course-set-state-handler
                    (list (cons :id id)
                          (cons "state" "garbage")))))
          (ok (= 400 (response-status res))))))))

(deftest course-list-pill-renders-state-dropdown
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Rowable" :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (let* ((res (courses-me-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search (format nil "/dashboard/courses/~A/state" id) body))
          (ok (search "published-public" body))
          (ok (search "published-private" body)))))))

(deftest course-confirm-delete-401-anonymous
  (with-mock-session (make-session)
    (let ((res (course-confirm-delete-handler '((:id . "x")))))
      (ok (= 401 (response-status res))))))

(deftest course-confirm-delete-404-missing
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((res (course-confirm-delete-handler
                    '((:id . "00000000-0000-0000-0000-000000000000")))))
          (ok (= 404 (response-status res))))))))

(deftest course-confirm-delete-403-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (c (create-course! :title "Owned" :author owner-dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user other)
        (let ((res (course-confirm-delete-handler (list (cons :id id)))))
          (ok (= 403 (response-status res))))))))

(deftest course-confirm-delete-renders-modal-for-owner
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Doomed" :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (let* ((res (course-confirm-delete-handler (list (cons :id id))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "modal-overlay" body))
          (ok (search "Delete this course?" body))
          (ok (search (format nil "hx-post=\"/dashboard/courses/~A/delete\"" id) body))
          (ok (search "Delete course" body)))))))

(deftest course-delete-redirects-anonymous
  (with-mock-session (make-session)
    (let ((res (course-delete-handler '((:id . "x")))))
      (ok (= 302 (response-status res)))
      (ok (string= "/login" (response-location res))))))

(deftest course-delete-403-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (c (create-course! :title "Owned" :author owner-dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user other)
        (with-mock-request (:htmx t)
          (let ((res (course-delete-handler (list (cons :id id)))))
            (ok (= 403 (response-status res)))))))))

(deftest course-delete-404-missing
  ;; Regression: the null-course branch used to call an undefined (not-found),
  ;; crashing instead of returning 404 for a delete of a non-existent course.
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((res (course-delete-handler
                    '((:id . "00000000-0000-0000-0000-000000000000")))))
          (ok (= 404 (response-status res))))))))

(deftest course-delete-htmx-returns-oob-row
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Bye" :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (with-mock-request (:htmx t)
          (let* ((res (course-delete-handler (list (cons :id id))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search (format nil "course-row-~A" id) body))
            (ok (search "hx-swap-oob" body))
            (ok (null (get-course-by-id id)))))))))

(deftest course-delete-non-htmx-redirects
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Bye" :author dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user user)
        (with-mock-request (:htmx nil)
          (let ((res (course-delete-handler (list (cons :id id)))))
            (ok (= 302 (response-status res)))
            (ok (string= "/dashboard/courses" (response-location res)))))))))

(deftest course-add-notebook-401-anonymous
  (with-mock-session (make-session)
    (let ((res (course-add-notebook-handler
                '((:id . "00000000-0000-0000-0000-000000000000")
                  ("notebook_id" . "x")))))
      (ok (= 401 (response-status res))))))

(deftest course-add-notebook-404-missing-course
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((res (course-add-notebook-handler
                    '((:id . "00000000-0000-0000-0000-000000000000")
                      ("notebook_id" . "x")))))
          (ok (= 404 (response-status res))))))))

(deftest course-add-notebook-403-non-owner
  (with-test-db
    (let* ((owner (mk-user))
           (other (mk-user))
           (owner-dao (get-user-by-id (getf owner :id)))
           (c (create-course! :title "Owned" :author owner-dao))
           (id (princ-to-string (course-id c))))
      (with-mock-session (make-session :user other)
        (let ((res (course-add-notebook-handler
                    (list (cons :id id)
                          (cons "notebook_id" "x")))))
          (ok (= 403 (response-status res))))))))

(deftest course-add-notebook-attaches-and-renders-list
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Course" :author dao))
           (course-uuid (course-id c))
           (course-id-str (princ-to-string course-uuid))
           (nb (create-notebook!
                :title "Attachable"
                :body-md "===prose===
hi"
                :cells nil
                :status "published"
                :published-at (local-time:now)
                :author dao))
           (nb-id-str (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let* ((res (course-add-notebook-handler
                     (list (cons :id course-id-str)
                           (cons "notebook_id" nb-id-str))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "course-notebooks-list" body))
          (ok (search "Attachable" body))
          (let ((rows (list-course-notebooks course-uuid)))
            (ok (= 1 (length rows)))))))))

(deftest course-add-notebook-rejects-duplicate
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (c (create-course! :title "Course" :author dao))
           (course-uuid (course-id c))
           (course-id-str (princ-to-string course-uuid))
           (nb (create-notebook!
                :title "Once"
                :body-md "===prose===
hi"
                :cells nil
                :status "published"
                :published-at (local-time:now)
                :author dao))
           (nb-id-str (princ-to-string (notebook-id nb))))
      (add-notebook-to-course! course-uuid (notebook-id nb))
      (with-mock-session (make-session :user user)
        (let* ((res (course-add-notebook-handler
                     (list (cons :id course-id-str)
                           (cons "notebook_id" nb-id-str))))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "already attached" body))
          (let ((rows (list-course-notebooks course-uuid)))
            (ok (= 1 (length rows)))))))))

(defun %attach-n-notebooks (n &key user)
  "Create COURSE owned by USER and attach N notebooks at positions 0..N-1.

Returns (values course-id-uuid course-id-str (list cn-id ...) (list nb-id-str ...))
where the lists are aligned with the attached positions."
  (let* ((dao (get-user-by-id (getf user :id)))
         (c (create-course! :title "Course" :author dao))
         (course-uuid (course-id c))
         (course-id-str (princ-to-string course-uuid))
         (nbs (loop for i from 0 below n
                    collect (create-notebook!
                             :title (format nil "N~D" i)
                             :body-md (format nil "===prose===~%body~D" i)
                             :cells nil
                             :status "published"
                             :published-at (local-time:now)
                             :author dao))))
    (loop for nb in nbs
          for i from 0
          do (add-notebook-to-course! course-uuid (notebook-id nb)
                                      :position i))
    (let* ((rows (list-course-notebooks course-uuid))
           (cn-ids (mapcar #'course-notebook-id rows))
           (nb-id-strs
             (mapcar (lambda (nb) (princ-to-string (notebook-id nb))) nbs)))
      (values course-uuid course-id-str cn-ids nb-id-strs))))

(deftest course-notebook-move-up-401-anonymous
  (with-mock-session (make-session)
    (let ((res (course-notebook-move-up-handler
                '((:id . "00000000-0000-0000-0000-000000000000")
                  (:cn-id . "1")))))
      (ok (= 401 (response-status res))))))

(deftest course-notebook-move-up-403-non-owner
  (with-test-db
    (let ((owner (mk-user))
          (other (mk-user)))
      (multiple-value-bind (course-uuid course-id-str cn-ids nb-ids)
          (%attach-n-notebooks 2 :user owner)
        (declare (ignore course-uuid nb-ids))
        (with-mock-session (make-session :user other)
          (let ((res (course-notebook-move-up-handler
                      (list (cons :id course-id-str)
                            (cons :cn-id (princ-to-string (second cn-ids)))))))
            (ok (= 403 (response-status res)))))))))

(deftest course-notebook-move-up-swaps-positions
  (with-test-db
    (let ((user (mk-user)))
      (multiple-value-bind (course-uuid course-id-str cn-ids nb-ids)
          (%attach-n-notebooks 3 :user user)
        (declare (ignore nb-ids))
        (with-mock-session (make-session :user user)
          ;; Move position 2 (third notebook) up -> ends up at position 1.
          (let* ((target (third cn-ids))
                 (res (course-notebook-move-up-handler
                       (list (cons :id course-id-str)
                             (cons :cn-id (princ-to-string target))))))
            (ok (= 200 (response-status res)))
            (ok (search "course-notebooks-list" (first (response-body res))))
            (let* ((rows (list-course-notebooks course-uuid))
                   (positions
                    (mapcar (lambda (r)
                              (cons (course-notebook-id r)
                                    (course-notebook-position r)))
                            rows)))
              (ok (= 0 (cdr (assoc (first cn-ids) positions))))
              (ok (= 2 (cdr (assoc (second cn-ids) positions))))
              (ok (= 1 (cdr (assoc (third cn-ids) positions)))))))))))

(deftest course-notebook-move-up-noop-at-top
  (with-test-db
    (let ((user (mk-user)))
      (multiple-value-bind (course-uuid course-id-str cn-ids nb-ids)
          (%attach-n-notebooks 3 :user user)
        (declare (ignore nb-ids))
        (with-mock-session (make-session :user user)
          (let ((res (course-notebook-move-up-handler
                      (list (cons :id course-id-str)
                            (cons :cn-id (princ-to-string (first cn-ids)))))))
            (ok (= 200 (response-status res)))
            (let* ((rows (list-course-notebooks course-uuid))
                   (positions
                    (mapcar (lambda (r)
                              (cons (course-notebook-id r)
                                    (course-notebook-position r)))
                            rows)))
              (ok (= 0 (cdr (assoc (first cn-ids) positions))))
              (ok (= 1 (cdr (assoc (second cn-ids) positions))))
              (ok (= 2 (cdr (assoc (third cn-ids) positions)))))))))))

(deftest course-notebook-move-down-swaps-positions
  (with-test-db
    (let ((user (mk-user)))
      (multiple-value-bind (course-uuid course-id-str cn-ids nb-ids)
          (%attach-n-notebooks 3 :user user)
        (declare (ignore nb-ids))
        (with-mock-session (make-session :user user)
          ;; Move position 0 (first notebook) down -> ends up at position 1.
          (let* ((target (first cn-ids))
                 (res (course-notebook-move-down-handler
                       (list (cons :id course-id-str)
                             (cons :cn-id (princ-to-string target))))))
            (ok (= 200 (response-status res)))
            (ok (search "course-notebooks-list" (first (response-body res))))
            (let* ((rows (list-course-notebooks course-uuid))
                   (positions
                    (mapcar (lambda (r)
                              (cons (course-notebook-id r)
                                    (course-notebook-position r)))
                            rows)))
              (ok (= 1 (cdr (assoc (first cn-ids) positions))))
              (ok (= 0 (cdr (assoc (second cn-ids) positions))))
              (ok (= 2 (cdr (assoc (third cn-ids) positions)))))))))))

(deftest course-notebook-move-down-noop-at-bottom
  (with-test-db
    (let ((user (mk-user)))
      (multiple-value-bind (course-uuid course-id-str cn-ids nb-ids)
          (%attach-n-notebooks 3 :user user)
        (declare (ignore nb-ids))
        (with-mock-session (make-session :user user)
          (let ((res (course-notebook-move-down-handler
                      (list (cons :id course-id-str)
                            (cons :cn-id (princ-to-string (third cn-ids)))))))
            (ok (= 200 (response-status res)))
            (let* ((rows (list-course-notebooks course-uuid))
                   (positions
                    (mapcar (lambda (r)
                              (cons (course-notebook-id r)
                                    (course-notebook-position r)))
                            rows)))
              (ok (= 0 (cdr (assoc (first cn-ids) positions))))
              (ok (= 1 (cdr (assoc (second cn-ids) positions))))
              (ok (= 2 (cdr (assoc (third cn-ids) positions)))))))))))

(deftest course-notebook-remove-401-anonymous
  (with-mock-session (make-session)
    (let ((res (course-notebook-remove-handler
                '((:id . "00000000-0000-0000-0000-000000000000")
                  (:cn-id . "1")))))
      (ok (= 401 (response-status res))))))

(deftest course-notebook-remove-403-non-owner
  (with-test-db
    (let ((owner (mk-user))
          (other (mk-user)))
      (multiple-value-bind (course-uuid course-id-str cn-ids nb-ids)
          (%attach-n-notebooks 1 :user owner)
        (declare (ignore course-uuid nb-ids))
        (with-mock-session (make-session :user other)
          (let ((res (course-notebook-remove-handler
                      (list (cons :id course-id-str)
                            (cons :cn-id
                                  (princ-to-string (first cn-ids)))))))
            (ok (= 403 (response-status res)))))))))

(deftest course-notebook-remove-deletes-and-rerenders
  (with-test-db
    (let ((user (mk-user)))
      (multiple-value-bind (course-uuid course-id-str cn-ids nb-ids)
          (%attach-n-notebooks 2 :user user)
        (declare (ignore nb-ids))
        (with-mock-session (make-session :user user)
          (let* ((target (first cn-ids))
                 (res (course-notebook-remove-handler
                       (list (cons :id course-id-str)
                             (cons :cn-id (princ-to-string target)))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "course-notebooks-list" body))
            ;; N0 is gone from the attached <li> rows but reappears as an
            ;; eligible <option>. Check it no longer carries an nb-title span.
            (ng (search "<span class=nb-title>N0" body))
            (ok (search "<span class=nb-title>N1" body))
            (let ((rows (list-course-notebooks course-uuid)))
              (ok (= 1 (length rows)))
              (ok (= (second cn-ids)
                     (course-notebook-id (first rows)))))))))))

(deftest public-course-handler-shows-attached-notebooks-in-order
  (testing "GET /c/@:handle/:slug renders attached notebooks in position order"
    (with-test-db
      (let* ((author (mk-user))
             (dao (get-user-by-id (getf author :id)))
             (handle (recurya/db/users:users-handle dao))
             (course (create-course! :title "Ordered"
                                     :status "published"
                                     :visibility "public"
                                     :published-at (local-time:now)
                                     :author dao))
             (course-uuid (course-id course))
             (slug (course-slug course))
             (nb-a (create-notebook!
                    :title "Notebook-A"
                    :body-md (format nil "===prose===~%a")
                    :cells nil
                    :status "published"
                    :visibility "public"
                    :published-at (local-time:now)
                    :author dao))
             (nb-b (create-notebook!
                    :title "Notebook-B"
                    :body-md (format nil "===prose===~%b")
                    :cells nil
                    :status "published"
                    :visibility "public"
                    :published-at (local-time:now)
                    :author dao))
             (nb-c (create-notebook!
                    :title "Notebook-C"
                    :body-md (format nil "===prose===~%c")
                    :cells nil
                    :status "published"
                    :visibility "public"
                    :published-at (local-time:now)
                    :author dao)))
        (add-notebook-to-course! course-uuid (notebook-id nb-a) :position 0)
        (add-notebook-to-course! course-uuid (notebook-id nb-b) :position 1)
        (add-notebook-to-course! course-uuid (notebook-id nb-c) :position 2)
        (with-mock-session (make-session)
          (let* ((res (public-course-by-handle-handler
                       (list (cons :captures (list handle slug)))))
                 (body (first (response-body res)))
                 (pa (search "Notebook-A" body))
                 (pb (search "Notebook-B" body))
                 (pc (search "Notebook-C" body)))
            (ok (= 200 (response-status res)))
            (ok pa)
            (ok pb)
            (ok pc)
            (ok (and pa pb (< pa pb)))
            (ok (and pb pc (< pb pc)))))))))

(deftest courses-public-handler-shows-published-only
  (with-test-db
    (let* ((author (mk-user))
           (dao (get-user-by-id (getf author :id))))
      (create-course! :title "Pub Course"
                      :status "published"
                      :visibility "public"
                      :published-at (local-time:now)
                      :author dao)
      (create-course! :title "Drafty Course"
                      :status "draft"
                      :author dao)
      (with-mock-session (make-session)
        (let* ((res (courses-public-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "Pub Course" body))
          (ng (search "Drafty Course" body)))))))

(deftest courses-public-handler-shows-only-public
  (with-test-db
    (let* ((author (mk-user))
           (dao (get-user-by-id (getf author :id))))
      (create-course! :title "PubPub Course"
                      :status "published" :visibility "public"
                      :published-at (local-time:now) :author dao)
      (create-course! :title "PubPriv Course"
                      :status "published" :visibility "private"
                      :published-at (local-time:now) :author dao)
      (with-mock-session (make-session)
        (let* ((res (courses-public-handler nil))
               (body (first (response-body res))))
          (ok (= 200 (response-status res)))
          (ok (search "PubPub Course" body))
          (ng (search "PubPriv Course" body)))))))

(deftest courses-public-handler-anonymous-200
  (with-test-db
    (with-mock-session (make-session)
      (let ((res (courses-public-handler nil)))
        (ok (= 200 (response-status res)))
        (ok (search "Courses" (first (response-body res))))))))

(deftest courses-public-handler-includes-slug-link
  (testing "course card links use /c/@<handle>/<slug> when handle is set"
    (with-test-db
      (let* ((author (mk-user))
             (dao (get-user-by-id (getf author :id)))
             (handle (users-handle dao))
             (course (create-course! :title "Slug Linked"
                                     :status "published"
                                     :visibility "public"
                                     :published-at (local-time:now)
                                     :author dao))
             (slug (course-slug course)))
        (with-mock-session (make-session)
          (let* ((res (courses-public-handler nil))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search (format nil "/c/@~A/~A" handle slug) body))))))))

(deftest courses-public-handler-empty-state
  (with-test-db
    (with-mock-session (make-session)
      (let* ((res (courses-public-handler nil))
             (body (first (response-body res))))
        (ok (= 200 (response-status res)))
        (ok (search "No courses yet" body))))))

(deftest course-by-handle-different-authors-same-slug-isolated
  (testing "GET /c/@:handle/:slug isolates courses by author"
    (with-test-db
      (let ((alice-dao (create-test-user :email-prefix "alice"
                                         :handle "alice-c7b"))
            (bob-dao (create-test-user :email-prefix "bob"
                                       :handle "bob-c7b")))
        (create-course! :title "Alice course" :slug "intro"
                        :status "published" :visibility "public"
                        :published-at (local-time:now) :author alice-dao)
        (create-course! :title "Bob course" :slug "intro"
                        :status "published" :visibility "public"
                        :published-at (local-time:now) :author bob-dao)
        (with-mock-session (make-session)
          (let ((res-alice
                 (public-course-by-handle-handler
                  '((:captures . ("alice-c7b" "intro")))))
                (res-bob
                 (public-course-by-handle-handler
                  '((:captures . ("bob-c7b" "intro"))))))
            (ok (= 200 (response-status res-alice)))
            (ok (= 200 (response-status res-bob)))
            (ok (search "Alice course" (first (response-body res-alice))))
            (ng (search "Bob course" (first (response-body res-alice))))
            (ok (search "Bob course" (first (response-body res-bob))))
            (ng (search "Alice course" (first (response-body res-bob))))))))))

(deftest course-by-handle-404-unknown-handle
  (with-test-db
    (with-mock-session (make-session)
      (let ((res (public-course-by-handle-handler
                  '((:captures . ("ghost-c7b" "intro"))))))
        (ok (= 404 (response-status res)))))))

(deftest course-by-handle-draft-private-404
  (testing "draft+private course is not visible to others via @handle"
    (with-test-db
      (let ((dao (create-test-user :email-prefix "draft-c"
                                   :handle "draftc-c7b")))
        (create-course! :title "Draft" :slug "draft-only"
                        :status "draft" :author dao)
        (with-mock-session (make-session)
          (let ((res (public-course-by-handle-handler
                      '((:captures . ("draftc-c7b" "draft-only"))))))
            (ok (= 404 (response-status res)))))))))

(deftest course-create-handler-persists-visibility-unlisted
  (with-test-db
    (let ((user (mk-user)))
      (with-mock-session (make-session :user user)
        (let ((params '(("title" . "Unlisted Course")
                        ("slug" . "")
                        ("summary" . "")
                        ("status" . "published")
                        ("visibility" . "unlisted"))))
          (course-create-handler params)
          (let ((c (get-course-by-slug "unlisted-course")))
            (ok c)
            (ok (string= "unlisted" (course-visibility c)))))))))

(deftest course-set-state-published-unlisted
  (testing "set-state published-unlisted persists unlisted and returns the
4-state dropdown with an Unlisted summary pill"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (c (create-course! :title "S" :author dao
                                :status "draft" :visibility "private"))
             (id (princ-to-string (course-id c))))
        (with-mock-session (make-session :user user)
          (let* ((res (course-set-state-handler
                       (list (cons :id id)
                             (cons "state" "published-unlisted"))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res)))
            (ok (search "status-unlisted" body))
            (ok (search "&quot;state&quot;:&quot;published-unlisted&quot;" body))
            (let ((after (get-course-by-id id)))
              (ok (string= "published" (course-status after)))
              (ok (string= "unlisted" (course-visibility after))))))))))

(deftest dashboard-shows-copy-link-for-unlisted-course-only
  (testing "an unlisted course row exposes a copy-link affordance"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id))))
        (create-course! :title "UnlistedC" :slug "unlisted-c"
                        :status "published" :visibility "unlisted"
                        :published-at (local-time:now) :author dao)
        (with-mock-session (make-session :user user)
          (let ((body (first (response-body (courses-me-handler nil)))))
            (ok (search "copy-link-btn" body))
            (ok (search "data-share-url" body))
            (ok (search (format nil "/c/@~A/unlisted-c" (getf user :handle))
                        body))))))))

(deftest unlisted-course-page-has-noindex
  (testing "an unlisted course page carries robots=noindex; a public one does not"
    (with-test-db
      (let* ((dao (create-test-user :email-prefix "ix" :handle "ixc-7b"))
             (handle (users-handle dao)))
        (create-course! :title "U" :slug "u-c"
                        :status "published" :visibility "unlisted"
                        :published-at (local-time:now) :author dao)
        (create-course! :title "P" :slug "p-c"
                        :status "published" :visibility "public"
                        :published-at (local-time:now) :author dao)
        (with-mock-session (make-session)
          (let ((u-body (first (response-body
                                (public-course-by-handle-handler
                                 `((:captures . (,handle "u-c")))))))
                (p-body (first (response-body
                                (public-course-by-handle-handler
                                 `((:captures . (,handle "p-c"))))))))
            (ok (search "noindex" u-body))
            (ng (search "noindex" p-body))))))))

(deftest unlisted-course-absent-from-public-listing
  (testing "an unlisted course does not appear on /courses"
    (with-test-db
      (let ((dao (create-test-user :email-prefix "hidc" :handle "hidc-7b")))
        (create-course! :title "HiddenCourse" :slug "hidden-course"
                        :status "published" :visibility "unlisted"
                        :published-at (local-time:now) :author dao)
        (with-mock-session (make-session)
          (let ((listing (first (response-body (courses-public-handler nil)))))
            (ng (search "HiddenCourse" listing))))))))

(deftest public-course-hides-non-public-member-notebooks
  (testing "the public course page lists only publicly-listable member
notebooks; an unlisted member is dropped from the public discovery surface"
    (with-test-db
      (let* ((dao (create-test-user :email-prefix "cm" :handle "cm-7b"))
             (handle (users-handle dao))
             (course (create-course! :title "Mixed" :slug "mixed"
                                     :status "published" :visibility "public"
                                     :published-at (local-time:now) :author dao))
             (pub (create-notebook! :title "PublicMember" :slug "pub-member"
                                    :body-md "===prose===
hi" :cells nil :author dao
                                    :status "published" :visibility "public"
                                    :published-at (local-time:now)))
             (unl (create-notebook! :title "UnlistedMember" :slug "unl-member"
                                    :body-md "===prose===
hi" :cells nil :author dao
                                    :status "published" :visibility "unlisted"
                                    :published-at (local-time:now))))
        (add-notebook-to-course! (course-id course) (notebook-id pub) :position 0)
        (add-notebook-to-course! (course-id course) (notebook-id unl) :position 1)
        (with-mock-session (make-session)
          (let ((body (first (response-body
                              (public-course-by-handle-handler
                               `((:captures . (,handle "mixed"))))))))
            (ok (search "PublicMember" body) "public member is listed")
            (ng (search "UnlistedMember" body) "unlisted member is hidden")
            (ng (search "/@cm-7b/unl-member" body)
                "no link to the unlisted member")))))))

(deftest public-course-page-shows-owner-their-private-member
  (testing "the course owner sees their own attached private notebook on the
course page (a public viewer would not); the page filter is viewer-aware."
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (handle (users-handle dao))
             (course (create-course! :title "Priv Course" :slug "priv-course"
                                     :status "published" :visibility "private"
                                     :published-at (local-time:now) :author dao))
             (nb (create-notebook! :title "PrivMember"
                                   :body-md (format nil "===prose===~%hi")
                                   :cells nil :author dao :status "published"
                                   :visibility "private"
                                   :published-at (local-time:now))))
        (add-notebook-to-course! (course-id course) (notebook-id nb) :position 0)
        (with-mock-session (make-session :user user)
          (let* ((res (public-course-by-handle-handler
                       (list (cons :captures (list handle (course-slug course))))))
                 (body (first (response-body res))))
            (ok (= 200 (response-status res))
                "owner may view their own private course")
            (ok (search "PrivMember" body)
                "owner sees their attached published+private notebook")))))))
