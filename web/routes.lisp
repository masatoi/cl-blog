;;;; web/routes.lisp --- Route handlers for the Ningle web application.
;;;;
;;;; Maps URL paths to handler functions for authentication, blog post
;;;; management, account settings, and public blog pages.  Includes
;;;; helpers for session management, pagination, and HTMX fragment
;;;; responses (status pills, confirmation modals, OOB swaps).

(defpackage #:recurya/web/routes
  (:use #:cl)
  (:import-from #:recurya/web/oauth)
  (:import-from #:recurya/db/users
                #:update-user!
                #:get-user-by-id
                #:get-user-by-handle
                #:find-or-create-oauth-user
                #:placeholder-handle-p)
  (:import-from #:recurya/web/ui/login)
  (:import-from #:recurya/web/ui/errors)
  (:import-from #:recurya/web/ui/account)
  (:import-from #:recurya/web/ui/onboarding)
  (:import-from #:recurya/web/ui/csrf)
  (:import-from #:recurya/utils/handle)
  (:import-from #:spinneret #:with-html-string)
  (:import-from #:lack/request #:request-env)
  (:import-from #:recurya/web/ui/notebooks-dashboard
                #:render-notebook-state-dropdown)
  (:import-from #:recurya/web/ui/notebook-form)
  (:import-from #:recurya/web/ui/notebook-list)
  (:import-from #:recurya/web/ui/course)
  (:import-from #:recurya/web/ui/course-list)
  (:import-from #:recurya/web/ui/courses #:render-course-state-dropdown)
  (:import-from #:recurya/web/ui/course-form)
  (:import-from #:recurya/web/ui/profile #:render-profile-page)
  ;; Note: recurya/db/notebooks exports a `notebook-cells` accessor that
  ;; collides with recurya/game/notebook:notebook-cells (a struct accessor).
  ;; The DB accessor is not used directly here (we use
  ;; recurya/db/notebooks:notebook-cells-parsed via package qualification),
  ;; so it is intentionally NOT imported below.
  (:import-from #:recurya/db/notebooks
                #:create-notebook!
                #:get-notebook-by-id
                #:find-notebook-by-handle-and-slug
                #:list-public-notebooks-of
                #:update-notebook!
                #:delete-notebook!
                #:list-notebooks
                #:count-notebooks
                #:notebook-id
                #:notebook-slug
                #:notebook-title
                #:notebook-summary
                #:notebook-body-md
                #:notebook-status
                #:notebook-visibility
                #:notebook-published-at
                #:notebook-author
                #:notebook-author-id
                #:notebook-created-at
                #:notebook-updated-at)
  (:import-from #:recurya/db/courses
                #:create-course!
                #:get-course-by-id
                #:get-course-by-slug
                #:find-course-by-handle-and-slug
                #:list-public-courses-of
                #:update-course!
                #:delete-course!
                #:list-courses
                #:count-courses
                #:course-id
                #:course-slug
                #:course-title
                #:course-summary
                #:course-status
                #:course-visibility
                #:course-published-at
                #:course-author
                #:course-author-id
                #:course-created-at
                #:course-updated-at)
  (:import-from #:recurya/db/course-notebooks
                #:count-course-notebooks
                #:list-course-notebooks
                #:add-notebook-to-course!
                #:remove-notebook-from-course!
                #:move-notebook-up!
                #:move-notebook-down!
                #:get-course-notebook
                #:course-notebook-id
                #:course-notebook-course-id
                #:course-notebook-position
                #:course-notebook-notebook
                #:course-notebook-notebook-id)
  (:import-from #:recurya/game/notebook-parser #:parse-notebook-body)
  (:import-from #:recurya/game/notebook
                #:cell-id
                #:cell-kind
                #:make-notebook
                #:notebook-cells
                #:run-cell
                #:notebook-cell-result-status
                #:notebook-cell-result-cell-id)
  (:import-from #:recurya/web/ui/notebook)
  (:import-from #:recurya/game/notebook-jsonb
                #:cell->jsonb-form
                #:jsonb-hash->cell)
  (:import-from #:recurya/db/learn
                #:upsert-cell-code
                #:user-cell-codes
                #:user-passed-cells
                #:mark-cell-passed
                #:record-submission
                #:merge-localstorage)
  (:import-from #:recurya/utils/common #:parse-json #:json->string)
  (:export #:setup-routes
           #:dashboard-home-handler
           #:account-confirm-delete-handler
           #:account-delete-handler
           #:onboarding-handle-page-handler
           #:onboarding-handle-create-handler
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
           #:profile-handler
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
           #:courses-public-handler
           #:learn-sync-handler
           #:sicp-learn-redirect-handler
           #:sicp-notebook-redirect-handler
           #:sicp-cell-run-redirect-handler
           #:learn-sync-redirect-handler
           #:+sicp-author-handle+))

(in-package #:recurya/web/routes)

;;; Response helpers

(defun html-response (body &key (status 200))
  "Create an HTML response."
  (list status '(:content-type "text/html; charset=utf-8") (list body)))

(defun redirect (location)
  "Create a redirect response."
  (list 302 (list :location location) (list "")))

(defun json-response (data &key (status 200))
  "Return a Clack ring response with JSON content."
  (list status
        '(:content-type "application/json; charset=utf-8")
        (list (json->string data))))

(defun %read-request-body ()
  "Read the raw POST body as a UTF-8 string, or empty string if unavailable."
  (let* ((env (lack/request:request-env ningle/context:*request*))
         (stream (getf env :raw-body))
         (content-length (or (getf env :content-length) 0)))
    (cond
      ((and stream (plusp content-length))
       (ignore-errors (file-position stream 0))
       (let ((buf (make-array content-length :element-type '(unsigned-byte 8))))
         (read-sequence buf stream)
         (babel:octets-to-string buf :encoding :utf-8)))
      (t ""))))

(defun get-session ()
  "Get the session hash table from the context."
  ningle/context:*session*)

(defun set-session-user! (user)
  "Store user in session."
  (when ningle/context:*session*
    (setf (gethash :user ningle/context:*session*) user)))

(defun clear-session! ()
  "Clear the session."
  (when ningle/context:*session*
    (clrhash ningle/context:*session*)))

(defun get-param (params key)
  "Get a parameter value from the alist."
  (cdr (assoc key params :test #'string-equal)))

(defun get-path-param (params key)
  "Get a path parameter (keyword) from the alist."
  (cdr (assoc key params)))



(defparameter *page-size* 5
  "Number of items per page for pagination.")



(defun parse-page-param (params)
  "Parse the page parameter from query params. Returns 1 if invalid or missing."
  (let* ((page-str (get-param params "page"))
         (page (when page-str (parse-integer page-str :junk-allowed t))))
    (if (and page (plusp page))
        page
        1)))



(defun make-pagination (current-page total-count page-size base-url)
  "Create pagination info plist.
Returns plist with :current-page :total-pages :total-count :has-prev :has-next
:prev-url :next-url."
  (let* ((total-pages (max 1 (ceiling total-count page-size)))
         (current-page (min current-page total-pages))
         (has-prev (> current-page 1))
         (has-next (< current-page total-pages)))
    (list :current-page current-page
          :total-pages total-pages
          :total-count total-count
          :has-prev has-prev
          :has-next has-next
          :prev-url (when has-prev (format nil "~A?page=~A" base-url (1- current-page)))
          :next-url (when has-next (format nil "~A?page=~A" base-url (1+ current-page))))))

;;; Route handlers

(defun get-current-user ()
  "Get the current user from session."
  (when ningle/context:*session*
    (gethash :user ningle/context:*session*)))

(defun root-handler (params)
  "GET / - hybrid home: logged-in users -> /dashboard, anonymous -> /notebooks."
  (declare (ignore params))
  (if (get-current-user)
      (redirect "/dashboard")
      (redirect "/notebooks")))

(defun login-page-handler (params)
  "Handle GET /login - show login form."
  (declare (ignore params))
  (if (get-current-user)
      (redirect "/dashboard/notebooks")
      (html-response (recurya/web/ui/login:render))))

(defun logout-handler (params)
  "Handle POST /logout - clear session."
  (declare (ignore params))
  (clear-session!)
  (redirect "/login"))

(defun parse-admin-emails ()
  "Parse the ADMIN_OAUTH_EMAIL env var as a comma-separated list (lower-cased)."
  (let ((env (uiop:getenv "ADMIN_OAUTH_EMAIL")))
    (when (and env (plusp (length env)))
      (loop for raw in (cl-ppcre:split "," env)
            for trimmed = (string-trim '(#\Space #\Tab) raw)
            unless (string= trimmed "")
              collect (string-downcase trimmed)))))

(defun admin-email-p (email)
  "True if EMAIL appears in ADMIN_OAUTH_EMAIL (case-insensitive)."
  (and email
       (let ((lc (string-downcase email)))
         (member lc (parse-admin-emails) :test #'string=))))

(defun user-dao->plist (user)
  "Convert a USER mito instance to the session plist used elsewhere."
  (list :id (recurya/models/users:users-id user)
        :email (recurya/models/users:users-email user)
        :name (recurya/models/users:users-display-name user)
        :handle (recurya/models/users:users-handle user)
        :role (intern (string-upcase (recurya/models/users:users-role user)) :keyword)
        :provider (recurya/models/users:users-provider user)
        :language (recurya/models/users:users-language user)
        :timezone (recurya/models/users:users-timezone user)))

(defun oauth-start-handler (params)
  "Handle GET /auth/:provider/start - generate state and redirect to provider."
  (let* ((provider-name (get-path-param params :provider))
         (provider (and provider-name (recurya/web/oauth:find-provider provider-name))))
    (cond
      ((null provider)
       (html-response (recurya/web/ui/errors:not-found) :status 404))
      ((not (recurya/web/oauth:provider-configured-p provider))
       (html-response (recurya/web/ui/login:render
                       :error (format nil "OAuth provider ~A is not configured." provider-name))
                      :status 503))
      (t
       (let ((state (recurya/web/oauth:generate-state)))
         (when ningle/context:*session*
           (setf (gethash :oauth-state ningle/context:*session*) state)
           (setf (gethash :oauth-provider ningle/context:*session*) provider-name))
         (redirect (recurya/web/oauth:build-authorize-url provider state)))))))

(defun oauth-callback-handler (params)
  "Handle GET /auth/:provider/callback - validate state, exchange code, create session."
  (let* ((provider-name (get-path-param params :provider))
         (provider (and provider-name (recurya/web/oauth:find-provider provider-name)))
         (code (get-param params "code"))
         (state (get-param params "state"))
         (saved-state (and ningle/context:*session*
                           (gethash :oauth-state ningle/context:*session*)))
         (saved-provider (and ningle/context:*session*
                              (gethash :oauth-provider ningle/context:*session*))))
    (cond
      ((null provider)
       (html-response (recurya/web/ui/errors:not-found) :status 404))
      ((or (null code) (null state)
           (null saved-state)
           (not (string= state saved-state))
           (not (and saved-provider (string-equal provider-name saved-provider))))
       (html-response (recurya/web/ui/login:render
                       :error "Sign-in session expired. Please try again.")
                      :status 400))
      (t
       (when ningle/context:*session*
         (remhash :oauth-state ningle/context:*session*)
         (remhash :oauth-provider ningle/context:*session*))
       (handler-case
           (let* ((token (recurya/web/oauth:exchange-code provider code))
                  (info (and token (recurya/web/oauth:fetch-userinfo provider token)))
                  (email (and info (recurya/web/oauth:extract-email provider info token)))
                  (uid (and info (recurya/web/oauth:extract-uid provider info)))
                  (display-name (and info (recurya/web/oauth:extract-name provider info))))
             (cond
               ((or (null email) (null uid))
                (html-response (recurya/web/ui/login:render
                                :error "Could not retrieve a verified email from the provider.")
                               :status 400))
               (t
                (let* ((role (if (admin-email-p email) "admin" "user"))
                       (user (find-or-create-oauth-user
                              :provider provider-name
                              :provider-uid uid
                              :email email
                              :display-name display-name
                              :role role)))
                  (unless (string= (recurya/models/users:users-role user) role)
                    (update-user! (recurya/models/users:users-id user) :role role)
                    (setf user (get-user-by-id (recurya/models/users:users-id user))))
                  (set-session-user! (user-dao->plist user))
                  (redirect "/dashboard")))))
         (error (e)
           (declare (ignore e))
           (html-response (recurya/web/ui/login:render
                           :error "OAuth login failed. Please try again.")
                          :status 502)))))))

;;; Blog Post Handlers

(defun get-session-user-object ()
  "Get the current user as a Mito DAO object for FK references."
  (let ((user (get-current-user)))
    (when user
      (let ((user-id (getf user :id)))
        (when user-id
          (get-user-by-id user-id))))))

(defun notebook->plist (nb)
  "Convert a notebook DAO into a plist for UI rendering."
  (list :id (princ-to-string (notebook-id nb))
        :slug (notebook-slug nb)
        :title (notebook-title nb)
        :summary (notebook-summary nb)
        :body-md (notebook-body-md nb)
        :status (notebook-status nb)
        :visibility (notebook-visibility nb)
        :published-at (notebook-published-at nb)
        :created-at (notebook-created-at nb)
        :updated-at (notebook-updated-at nb)
        :author-id (notebook-author-id nb)))

(defun notebooks-handler (params)
  "Handle GET /dashboard/notebooks - admin notebook list (own notebooks)."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((user-id (getf user :id))
               (page (parse-page-param params))
               (total-count (count-notebooks :author-id user-id))
               (offset (* (1- page) *page-size*))
               (raw (list-notebooks :author-id user-id
                                         :limit *page-size*
                                         :offset offset))
               (notebooks (mapcar #'notebook->plist raw))
               (pagination (make-pagination page total-count *page-size*
                                            "/dashboard/notebooks")))
          (html-response
           (recurya/web/ui/notebooks-dashboard:render
            :user user :notebooks notebooks :pagination pagination))))))

(defun notebook-new-handler (params)
  "Handle GET /dashboard/notebooks/new - show new notebook form."
  (declare (ignore params))
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (html-response
         (recurya/web/ui/notebook-form:render :user user :cells-json "[]")))))

(defun notebook-create-handler (params)
  "Handle POST /dashboard/notebooks - create a new notebook."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((title (get-param params "title"))
               (slug (get-param params "slug"))
               (summary (get-param params "summary"))
               (body (get-param params "body"))
               (status (get-param params "status"))
               (visibility-raw (get-param params "visibility"))
               (visibility
                 (if (member visibility-raw '("private" "unlisted" "public") :test #'equal)
                     visibility-raw
                     "private")))
          (cond
            ((or (null title) (equal title ""))
             (html-response
              (recurya/web/ui/notebook-form:render
               :user user
               :notebook (list :title title :slug slug :summary summary
                               :body-md body :status status
                               :visibility visibility)
               :errors '((:line nil :message "Title is required.")))))
            ((or (null body) (equal body ""))
             (html-response
              (recurya/web/ui/notebook-form:render
               :user user
               :notebook (list :title title :slug slug :summary summary
                               :body-md body :status status
                               :visibility visibility)
               :errors '((:line nil :message "Body is required.")))))
            (t
             (multiple-value-bind (cells parse-errors)
                 (parse-notebook-body body)
               (cond
                 (parse-errors
                  (html-response
                   (recurya/web/ui/notebook-form:render
                    :user user
                    :notebook (list :title title :slug slug :summary summary
                                    :body-md body :status status
                                    :visibility visibility)
                    :errors parse-errors)))
                 (t
                  (let* ((slug-val (if (and slug (string/= slug "")) slug nil))
                         (summary-val (if (and summary (string/= summary "")) summary nil))
                         (published-at
                           (when (equal status "published") (local-time:now)))
                         (cells-plists (mapcar #'cell->jsonb-form cells)))
                    (create-notebook!
                     :title title :slug slug-val :summary summary-val
                     :body-md body :cells cells-plists
                     :status (or status "draft")
                     :visibility visibility
                     :published-at published-at
                     :author (get-session-user-object))
                    (redirect "/dashboard/notebooks")))))))))))

(defun notebook-edit-handler (params)
  "Handle GET /dashboard/notebooks/:id/edit - show edit form for existing notebook
(owner only)."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (nb (and id (get-notebook-by-id id))))
          (cond
            ((null nb)
             (html-response (recurya/web/ui/errors:not-found) :status 404))
            ((not (equal (princ-to-string (notebook-author-id nb))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let* ((cells (parse-notebook-body (notebook-body-md nb)))
                    (cells-json (or (json->string (mapcar #'cell->jsonb-form cells))
                                    "[]")))
               (html-response
                (recurya/web/ui/notebook-form:render
                 :user user :notebook (notebook->plist nb)
                 :cells-json cells-json)))))))))

(defun notebook-update-handler (params)
  "Handle POST /dashboard/notebooks/:id - update an existing notebook (owner only).
The previous body markdown is reparsed to recover stable cell ids, then the
new body is parsed with those ids carried forward where (kind, body,
description) match."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (existing (and id (get-notebook-by-id id))))
          (cond
            ((null existing)
             (html-response (recurya/web/ui/errors:not-found) :status 404))
            ((not (equal (princ-to-string (notebook-author-id existing))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let* ((title (get-param params "title"))
                    (slug (get-param params "slug"))
                    (summary (get-param params "summary"))
                    (body (get-param params "body"))
                    (status (get-param params "status"))
                    (visibility-raw (get-param params "visibility"))
                    (visibility
                      (cond
                        ((member visibility-raw '("private" "unlisted" "public")
                                 :test #'equal)
                         visibility-raw)
                        (visibility-raw "private")
                        (t (notebook-visibility existing)))))
               (cond
                 ((or (null title) (equal title ""))
                  (html-response
                   (recurya/web/ui/notebook-form:render
                    :user user
                    :notebook (list :id id :title title :slug slug
                                    :summary summary :body-md body
                                    :status status :visibility visibility)
                    :errors '((:line nil :message "Title is required.")))))
                 ((or (null body) (equal body ""))
                  (html-response
                   (recurya/web/ui/notebook-form:render
                    :user user
                    :notebook (list :id id :title title :slug slug
                                    :summary summary :body-md body
                                    :status status :visibility visibility)
                    :errors '((:line nil :message "Body is required.")))))
                 (t
                  (let ((existing-cells
                          (mapcar #'jsonb-hash->cell
                                  (coerce
                                   (recurya/db/notebooks:notebook-cells-parsed existing)
                                   'list))))
                    (multiple-value-bind (cells parse-errors)
                        (parse-notebook-body body existing-cells)
                      (cond
                        (parse-errors
                         (html-response
                          (recurya/web/ui/notebook-form:render
                           :user user
                           :notebook (list :id id :title title :slug slug
                                           :summary summary :body-md body
                                           :status status
                                           :visibility visibility)
                           :errors parse-errors)))
                        (t
                         (let* ((slug-val
                                  (if (and slug (string/= slug "")) slug nil))
                                (summary-val
                                  (if (and summary (string/= summary ""))
                                      summary
                                      nil))
                                (published-at
                                  (when (and (equal status "published")
                                             (not (equal
                                                   (notebook-status existing)
                                                   "published")))
                                    (local-time:now)))
                                (cells-plists
                                  (mapcar #'cell->jsonb-form cells)))
                           (update-notebook!
                            id :title title :slug slug-val :summary summary-val
                            :body-md body :cells cells-plists
                            :status (or status "draft")
                            :visibility visibility
                            :published-at published-at)
                           (redirect "/dashboard/notebooks")))))))))))))))

(defun course->plist (c)
  "Convert a course DAO into a plist for UI rendering. The :notebook-count
field is the number of notebooks attached to the course via course_notebook."
  (list :id (princ-to-string (course-id c))
        :slug (course-slug c)
        :title (course-title c)
        :summary (course-summary c)
        :status (course-status c)
        :visibility (course-visibility c)
        :published-at (course-published-at c)
        :created-at (course-created-at c)
        :updated-at (course-updated-at c)
        :author-id (course-author-id c)
        :notebook-count (count-course-notebooks (course-id c))))

(defun courses-me-handler (params)
  "Handle GET /dashboard/courses - admin course list (own courses)."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((user-id (getf user :id))
               (page (parse-page-param params))
               (total-count (count-courses :author-id user-id))
               (offset (* (1- page) *page-size*))
               (raw (list-courses :author-id user-id
                                  :limit *page-size*
                                  :offset offset))
               (courses (mapcar #'course->plist raw))
               (pagination (make-pagination page total-count *page-size*
                                            "/dashboard/courses")))
          (html-response
           (recurya/web/ui/courses:render
            :user user :courses courses :pagination pagination))))))

(defun course-new-handler (params)
  "Handle GET /dashboard/courses/new - show new course form."
  (declare (ignore params))
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (html-response
         (recurya/web/ui/course-form:render :user user)))))

(defun course-create-handler (params)
  "Handle POST /dashboard/courses - create a new course."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((title (get-param params "title"))
               (slug (get-param params "slug"))
               (summary (get-param params "summary"))
               (status (get-param params "status"))
               (visibility-raw (get-param params "visibility"))
               (visibility
                 (if (member visibility-raw '("private" "unlisted" "public") :test #'equal)
                     visibility-raw
                     "private")))
          (cond
            ((or (null title) (equal title ""))
             (html-response
              (recurya/web/ui/course-form:render
               :user user
               :course (list :title title :slug slug :summary summary
                             :status status :visibility visibility)
               :errors '((:line nil :message "Title is required.")))))
            (t
             (let* ((slug-val (if (and slug (string/= slug "")) slug nil))
                    (summary-val (if (and summary (string/= summary "")) summary nil))
                    (published-at
                      (when (equal status "published") (local-time:now))))
               (create-course!
                :title title :slug slug-val :summary summary-val
                :status (or status "draft")
                :visibility visibility
                :published-at published-at
                :author (get-session-user-object))
               (redirect "/dashboard/courses"))))))))

(defun course-notebook-row->plist (cn)
  "Convert a COURSE-NOTEBOOK DAO into a plist
\(:id :cn-id :title :position) where:

  :id      - the underlying notebook UUID string (used by the
             eligible-notebooks dedup logic).
  :cn-id   - the course-notebook BIGSERIAL primary key (used by the
             reorder/remove HTMX endpoints)."
  (let ((nb (course-notebook-notebook cn)))
    (list :id (princ-to-string (course-notebook-notebook-id cn))
          :cn-id (course-notebook-id cn)
          :title (when nb (notebook-title nb))
          :position (course-notebook-position cn))))

(defun course-eligible-notebooks (user-id attached-notebook-ids)
  "Return plists (:id :title) of USER-ID's published notebooks that are
not already attached. ATTACHED-NOTEBOOK-IDS is a list of UUID strings."
  (let* ((own
          (list-notebooks :status "published" :visibility "public"
                               :author-id user-id
                               :limit 1000))
         (attached-set
          (mapcar (lambda (x) (princ-to-string x)) attached-notebook-ids)))
    (loop for nb in own
          for nb-id = (princ-to-string (notebook-id nb))
          unless (member nb-id attached-set :test #'string=)
            collect (list :id nb-id :title (notebook-title nb)))))

(defun course-edit-handler (params)
  "Handle GET /dashboard/courses/:id/edit - show edit form for an existing course
(owner only). Includes the attached notebook list and Add dropdown
populated with the user's other published notebooks."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (c (and id (get-course-by-id id))))
          (cond
            ((null c)
             (html-response (recurya/web/ui/errors:not-found) :status 404))
            ((not (equal (princ-to-string (course-author-id c))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let* ((rows (list-course-notebooks (course-id c)))
                    (course-notebooks
                     (mapcar #'course-notebook-row->plist rows))
                    (attached-ids
                     (mapcar (lambda (p) (getf p :id)) course-notebooks))
                    (eligible
                     (course-eligible-notebooks (getf user :id)
                                                attached-ids)))
               (html-response
                (recurya/web/ui/course-form:render
                 :user user :course (course->plist c)
                 :course-notebooks course-notebooks
                 :eligible-notebooks eligible)))))))))

(defun course-update-handler (params)
  "Handle POST /dashboard/courses/:id - update an existing course (owner only)."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (existing (and id (get-course-by-id id))))
          (cond
            ((null existing)
             (html-response (recurya/web/ui/errors:not-found) :status 404))
            ((not (equal (princ-to-string (course-author-id existing))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let* ((title (get-param params "title"))
                    (slug (get-param params "slug"))
                    (summary (get-param params "summary"))
                    (status (get-param params "status"))
                    (visibility-raw (get-param params "visibility"))
                    (visibility
                      (cond
                        ((member visibility-raw '("private" "unlisted" "public")
                                 :test #'equal)
                         visibility-raw)
                        (visibility-raw "private")
                        (t (course-visibility existing)))))
               (cond
                 ((or (null title) (equal title ""))
                  (html-response
                   (recurya/web/ui/course-form:render
                    :user user
                    :course (list :id id :title title :slug slug
                                  :summary summary :status status
                                  :visibility visibility)
                    :errors '((:line nil :message "Title is required.")))))
                 (t
                  (let* ((slug-val (if (and slug (string/= slug "")) slug nil))
                         (summary-val (if (and summary (string/= summary ""))
                                          summary
                                          nil))
                         (published-at
                           (when (and (equal status "published")
                                      (not (equal (course-status existing)
                                                  "published")))
                             (local-time:now))))
                    (update-course!
                     id :title title :slug slug-val :summary summary-val
                     :status (or status "draft")
                     :visibility visibility
                     :published-at published-at)
                    (redirect "/dashboard/courses")))))))))))

(defun %decode-state-token (token)
  "Decode the new pill state TOKEN into (values STATUS VISIBILITY) or
NIL if invalid.

Tokens are:
  \"draft\"               -> (\"draft\" nil)         ; visibility unchanged
  \"published-private\"   -> (\"published\" \"private\")
  \"published-unlisted\"  -> (\"published\" \"unlisted\")
  \"published-public\"    -> (\"published\" \"public\")"
  (cond ((equal token "draft") (values "draft" nil))
        ((equal token "published-private")
         (values "published" "private"))
        ((equal token "published-unlisted")
         (values "published" "unlisted"))
        ((equal token "published-public")
         (values "published" "public"))
        (t nil)))

(defun course-set-state-handler (params)
  "Handle POST /dashboard/courses/:id/state with form param state= one of
draft|published-private|published-public.

Decodes into (status, visibility), updates the course, and returns the
updated <details> dropdown markup (summary pill + 3 state buttons) so
HTMX can swap the entire dropdown via outerHTML and keep it functional
after subsequent clicks. Owner-only."
  (let ((user (get-current-user)))
    (cond
      ((null user)
       (html-response "Unauthorized" :status 401))
      (t
       (let* ((id (get-path-param params :id))
              (state-token (get-param params "state"))
              (c (and id (get-course-by-id id))))
         (cond
           ((null c) (html-response "Not found" :status 404))
           ((not (equal (princ-to-string (course-author-id c))
                        (princ-to-string (getf user :id))))
            (html-response "Forbidden" :status 403))
           (t
            (multiple-value-bind (new-status new-vis)
                (%decode-state-token state-token)
              (cond
                ((null new-status)
                 (html-response "Bad request" :status 400))
                (t
                 (let* ((current-status (course-status c))
                        (current-vis (course-visibility c))
                        (effective-vis (or new-vis current-vis))
                        (published-at
                          (when (and (equal new-status "published")
                                     (not (equal current-status "published")))
                            (local-time:now))))
                   (update-course! id :status new-status
                                   :visibility effective-vis
                                   :published-at published-at)
                   (html-response
                    (render-course-state-dropdown id new-status
                                                  effective-vis)))))))))))))

(defun course-confirm-delete-handler (params)
  "Handle GET /dashboard/courses/:id/confirm-delete - return modal fragment for deletion."
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (let* ((id (get-path-param params :id))
               (c (and id (get-course-by-id id))))
          (cond ((null c) (html-response "Not found" :status 404))
                ((not (equal (princ-to-string (course-author-id c))
                             (princ-to-string (getf user :id))))
                 (html-response "Forbidden" :status 403))
                (t
                 (html-response
                  (render-confirm-modal
                   :title "Delete this course?"
                   :message (format nil
                                    "\"~A\" will be permanently deleted. This cannot be undone."
                                    (course-title c))
                   :confirm-hx-post (format nil "/dashboard/courses/~A/delete" id)
                   :confirm-label "Delete course"))))))))

(defun course-delete-handler (params)
  "Handle POST /dashboard/courses/:id/delete - delete course (owner only).
For HTMX requests returns an empty OOB row swap; otherwise redirects."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (c (and id (get-course-by-id id))))
          (cond ((null c)
                 (html-response (recurya/web/ui/errors:not-found) :status 404))
                ((not (equal (princ-to-string (course-author-id c))
                             (princ-to-string (getf user :id))))
                 (html-response "Forbidden" :status 403))
                (t
                 (delete-course! id)
                 (if (htmx-request-p)
                     (html-response
                      (with-html-string
                        (:tr :id (format nil "course-row-~A" id)
                             :hx-swap-oob "outerHTML")))
                     (redirect "/dashboard/courses"))))))))

(defun course-add-notebook-handler (params)
  "Handle POST /dashboard/courses/:id/notebooks - attach a notebook to a course.

Owner only. Reads NOTEBOOK_ID from the form body. Returns the updated
notebook list as an HTML fragment (#course-notebooks-list) suitable for
HTMX outerHTML swap. Duplicate attachments are caught and reported as a
flash message in the rendered list."
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (let* ((id (get-path-param params :id))
               (c (and id (get-course-by-id id))))
          (cond ((null c) (html-response "Not found" :status 404))
                ((not
                  (equal (princ-to-string (course-author-id c))
                         (princ-to-string (getf user :id))))
                 (html-response "Forbidden" :status 403))
                (t
                 (let* ((nb-id-raw (get-param params "notebook_id"))
                        (nb-id (and nb-id-raw (string/= nb-id-raw "")
                                    nb-id-raw))
                        (nb (and nb-id (get-notebook-by-id nb-id)))
                        (course-id (course-id c))
                        (message nil))
                   (cond
                     ((null nb)
                      (setf message "Selected notebook does not exist."))
                     ((not (equal (princ-to-string
                                   (notebook-author-id nb))
                                  (princ-to-string (getf user :id))))
                      (setf message "You can only add your own notebooks."))
                     (t
                      (handler-case
                          (add-notebook-to-course! course-id nb-id)
                        (error ()
                          (setf message
                                "This notebook is already attached.")))))
                   (let* ((rows (list-course-notebooks course-id))
                          (course-notebooks
                           (mapcar #'course-notebook-row->plist rows))
                          (attached-ids
                           (mapcar (lambda (p) (getf p :id))
                                   course-notebooks))
                          (eligible
                           (course-eligible-notebooks
                            (getf user :id) attached-ids)))
                     (html-response
                      (recurya/web/ui/course-form:render-course-notebooks-list
                       (course->plist c) course-notebooks eligible
                       :message message))))))))))

(defun %render-course-notebook-list-fragment (course user-id &key message)
  "Helper: re-render the #course-notebooks-list fragment for COURSE owned by
USER-ID. Returns an HTML response. Used by add/move/remove handlers."
  (let* ((cid (course-id course))
         (rows (list-course-notebooks cid))
         (course-notebooks (mapcar #'course-notebook-row->plist rows))
         (attached-ids (mapcar (lambda (p) (getf p :id)) course-notebooks))
         (eligible (course-eligible-notebooks user-id attached-ids)))
    (html-response
     (recurya/web/ui/course-form:render-course-notebooks-list
      (course->plist course) course-notebooks eligible :message message))))

(defun %lookup-course-notebook-row (course-id cn-id-raw)
  "Resolve the course-notebook join row identified by CN-ID-RAW and verify it
belongs to COURSE-ID. Returns the row, or NIL on parse failure / mismatch /
missing row."
  (let ((cn-id (typecase cn-id-raw
                 (string (parse-integer cn-id-raw :junk-allowed t))
                 (integer cn-id-raw)
                 (t nil))))
    (when cn-id
      (let ((row (get-course-notebook cn-id)))
        (when (and row
                   (equal (princ-to-string (course-notebook-course-id row))
                          (princ-to-string course-id)))
          row)))))

(defun course-notebook-move-up-handler (params)
  "Handle POST /dashboard/courses/:id/notebooks/:cn-id/up - move a course-notebook
one position up.

Owner only. Re-renders #course-notebooks-list as an HTMX outerHTML
fragment. No-op when already at position 0."
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (let* ((id (get-path-param params :id))
               (c (and id (get-course-by-id id))))
          (cond
            ((null c) (html-response "Not found" :status 404))
            ((not (equal (princ-to-string (course-author-id c))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let* ((cn-id-raw (get-path-param params :cn-id))
                    (row (%lookup-course-notebook-row (course-id c) cn-id-raw)))
               (cond
                 ((null row) (html-response "Not found" :status 404))
                 (t
                  (move-notebook-up! (course-notebook-id row))
                  (%render-course-notebook-list-fragment
                   c (getf user :id)))))))))))

(defun course-notebook-move-down-handler (params)
  "Handle POST /dashboard/courses/:id/notebooks/:cn-id/down - move a course-notebook
one position down.

Owner only. Re-renders #course-notebooks-list as an HTMX outerHTML
fragment. No-op when already at the last position."
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (let* ((id (get-path-param params :id))
               (c (and id (get-course-by-id id))))
          (cond
            ((null c) (html-response "Not found" :status 404))
            ((not (equal (princ-to-string (course-author-id c))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let* ((cn-id-raw (get-path-param params :cn-id))
                    (row (%lookup-course-notebook-row (course-id c) cn-id-raw)))
               (cond
                 ((null row) (html-response "Not found" :status 404))
                 (t
                  (move-notebook-down! (course-notebook-id row))
                  (%render-course-notebook-list-fragment
                   c (getf user :id)))))))))))

(defun course-notebook-remove-handler (params)
  "Handle POST /dashboard/courses/:id/notebooks/:cn-id/remove - detach a notebook
from a course.

Owner only. Re-renders #course-notebooks-list as an HTMX outerHTML
fragment with the row gone. We re-render the entire list (rather than
just the single row) for consistency with up/down — keeping the eligible
notebooks dropdown in sync."
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (let* ((id (get-path-param params :id))
               (c (and id (get-course-by-id id))))
          (cond
            ((null c) (html-response "Not found" :status 404))
            ((not (equal (princ-to-string (course-author-id c))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let* ((cn-id-raw (get-path-param params :cn-id))
                    (row (%lookup-course-notebook-row (course-id c) cn-id-raw)))
               (cond
                 ((null row) (html-response "Not found" :status 404))
                 (t
                  (remove-notebook-from-course!
                   (course-id c)
                   (course-notebook-notebook-id row))
                  (%render-course-notebook-list-fragment
                   c (getf user :id)))))))))))

(defun notebook-set-state-handler (params)
  "Handle POST /dashboard/notebooks/:id/state with form param state= one of
draft|published-private|published-public.

Decodes into (status, visibility), updates the notebook, and returns
the updated <details> dropdown markup (summary pill + 3 state buttons)
so HTMX can swap the entire dropdown via outerHTML and keep it
functional after subsequent clicks. Owner-only."
  (let ((user (get-current-user)))
    (cond
      ((null user)
       (html-response "Unauthorized" :status 401))
      (t
       (let* ((id (get-path-param params :id))
              (state-token (get-param params "state"))
              (nb (and id (get-notebook-by-id id))))
         (cond
           ((null nb) (html-response "Not found" :status 404))
           ((not (equal (princ-to-string (notebook-author-id nb))
                        (princ-to-string (getf user :id))))
            (html-response "Forbidden" :status 403))
           (t
            (multiple-value-bind (new-status new-vis)
                (%decode-state-token state-token)
              (cond
                ((null new-status)
                 (html-response "Bad request" :status 400))
                (t
                 (let* ((current-status (notebook-status nb))
                        (current-vis (notebook-visibility nb))
                        (effective-vis (or new-vis current-vis))
                        (published-at
                          (when (and (equal new-status "published")
                                     (not (equal current-status "published")))
                            (local-time:now))))
                   (update-notebook! id :status new-status
                                          :visibility effective-vis
                                          :published-at published-at)
                   (html-response
                    (render-notebook-state-dropdown id new-status
                                                         effective-vis)))))))))))))

(defun notebook-confirm-delete-handler (params)
  "Handle GET /dashboard/notebooks/:id/confirm-delete - return modal fragment for deletion."
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (let* ((id (get-path-param params :id))
               (nb (and id (get-notebook-by-id id))))
          (cond
            ((null nb) (html-response "Not found" :status 404))
            ((not (equal (princ-to-string (notebook-author-id nb))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (html-response
              (render-confirm-modal
               :title "Delete this notebook?"
               :message (format nil
                                "\"~A\" will be permanently deleted. This cannot be undone."
                                (notebook-title nb))
               :confirm-hx-post (format nil "/dashboard/notebooks/~A/delete" id)
               :confirm-label "Delete notebook"))))))))

(defun notebook-delete-handler (params)
  "Handle POST /dashboard/notebooks/:id/delete - delete notebook (owner only).
For HTMX requests returns an empty OOB row swap; otherwise redirects."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (nb (and id (get-notebook-by-id id))))
          (cond
            ((null nb)
             (html-response (recurya/web/ui/errors:not-found) :status 404))
            ((not (equal (princ-to-string (notebook-author-id nb))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (delete-notebook! id)
             (if (htmx-request-p)
                 (html-response
                  (with-html-string
                    (:tr :id (format nil "nb-row-~A" id)
                         :hx-swap-oob "outerHTML")))
                 (redirect "/dashboard/notebooks"))))))))

(defun notebook-public-plist (nb)
  "Convert a notebook DAO to a plist for the public listing UI.
Includes :author-handle so cards can link to /@<handle>/<slug> and
the @handle attribution badge."
  (let* ((author (notebook-author nb))
         (author-name
          (when author (recurya/models/users:users-display-name author)))
         (author-handle
          (when author (recurya/models/users:users-handle author))))
    (list :slug (notebook-slug nb)
          :title (notebook-title nb)
          :summary (notebook-summary nb)
          :published-at (notebook-published-at nb)
          :author-name (or author-name "Anonymous")
          :author-handle author-handle)))

(defun notebooks-public-handler (params)
  "Handle GET /notebooks - public listing of published notebooks.
No authentication required."
  (let* ((user (get-current-user))
         (page (parse-page-param params))
         (total-count (count-notebooks :status "published"
                                             :visibility "public"))
         (offset (* (1- page) *page-size*))
         (raw (list-notebooks :status "published"
                                   :visibility "public"
                                   :limit *page-size*
                                   :offset offset))
         (notebooks (mapcar #'notebook-public-plist raw))
         (pagination (make-pagination page total-count *page-size*
                                      "/notebooks")))
    (html-response
     (recurya/web/ui/notebook-list:render
      :notebooks notebooks :pagination pagination :user user))))

(defun notebook-row->notebook-struct (nb-row)
  "Convert a notebook DAO into a recurya/game/notebook:notebook struct
that the existing notebook UI and run-cell logic can consume.
Cells come from the JSONB cache (parsed via jsonb-hash->cell)."
  (let* ((cells-data (recurya/db/notebooks:notebook-cells-parsed nb-row))
         (cells-list (mapcar #'jsonb-hash->cell
                             (coerce (or cells-data #()) 'list))))
    (make-notebook
     :id (princ-to-string (notebook-id nb-row))
     :chapter ""
     :title (or (notebook-title nb-row) "")
     :summary (or (notebook-summary nb-row) "")
     :cells cells-list)))

(defun %render-public-notebook-response (nb-row params)
  "Render the public notebook page for NB-ROW given the request PARAMS.

Encapsulates the can-view check, optional ?course=<slug> sidebar,
breadcrumb, and prev/next URL logic for the handle-aware public
notebook handler.

Returns a Clack response list. Returns 404 when NB-ROW is NIL or the
viewer cannot view it."
  (let* ((user (get-current-user))
         (uid (and user (getf user :id))))
    (cond
      ((null nb-row)
       (html-response (recurya/web/ui/errors:not-found) :status 404))
      ((not (recurya/utils/access-control:can-view-notebook-p user nb-row))
       (html-response (recurya/web/ui/errors:not-found) :status 404))
      (t
       (let* ((notebook (notebook-row->notebook-struct nb-row))
              (nb-id-str (princ-to-string (notebook-id nb-row)))
              (saved (when uid (user-cell-codes uid nb-id-str)))
              (passed (when uid (user-passed-cells uid nb-id-str)))
              (author (notebook-author nb-row))
              (author-handle
               (and author (recurya/models/users:users-handle author)))
              (run-cell-base
               (when author-handle
                 (format nil "/@~A/~A" author-handle
                         (notebook-slug nb-row))))
              (course-slug-param (get-param params "course"))
              (course-row
               ;; Per-author slug uniqueness makes a bare ?course= slug
               ;; ambiguous, and the param is attacker-controllable. Only
               ;; honor the sidebar context for courses the viewer may
               ;; actually see (owner, published+public, or published+unlisted);
               ;; otherwise drop it so a private/draft course's title and
               ;; member notebook slugs never leak. Unlisted courses are
               ;; link-shareable, so surfacing their title/sibling slugs to a
               ;; viewer who already reached a member notebook is acceptable.
               ;; can-view-course-p tolerates a NIL course.
               (let ((c (and course-slug-param
                             (get-course-by-slug course-slug-param))))
                 (when (recurya/utils/access-control:can-view-course-p user c)
                   c)))
              (course-author
               (and course-row (course-author course-row)))
              (course-handle
               (and course-author
                    (recurya/models/users:users-handle course-author)))
              (course-rows
               (and course-row
                    (list-course-notebooks (course-id course-row))))
              (notebook-in-course-p
               (and course-rows
                    (find (princ-to-string (notebook-id nb-row))
                          course-rows
                          :key (lambda (cn)
                                 (princ-to-string
                                  (course-notebook-notebook-id cn)))
                          :test #'equal))))
         (cond
           (notebook-in-course-p
            (let* ((sidebar-notebooks
                    (mapcar #'course-notebook-row->public-plist course-rows))
                   (current-slug (notebook-slug nb-row))
                   (current-pos
                    (position current-slug sidebar-notebooks
                              :key (lambda (p) (getf p :slug))
                              :test #'string=))
                   (cs (course-slug course-row))
                   (prev-url
                    (when (and current-pos (> current-pos 0))
                      (let* ((prev (nth (1- current-pos)
                                        sidebar-notebooks))
                             (prev-handle (getf prev :author-handle))
                             (prev-slug (getf prev :slug)))
                        (when (and prev-handle prev-slug)
                          (format nil "/@~A/~A?course=~A"
                                  prev-handle prev-slug cs)))))
                   (next-url
                    (when (and current-pos
                               (< current-pos
                                  (1- (length sidebar-notebooks))))
                      (let* ((nxt (nth (1+ current-pos)
                                       sidebar-notebooks))
                             (nxt-handle (getf nxt :author-handle))
                             (nxt-slug (getf nxt :slug)))
                        (when (and nxt-handle nxt-slug)
                          (format nil "/@~A/~A?course=~A"
                                  nxt-handle nxt-slug cs)))))
                   (course-href
                    (when course-handle
                      (format nil "/c/@~A/~A" course-handle cs)))
                   (breadcrumb
                    (list (list :text "Notebooks" :href "/notebooks")
                          (list :text (course-title course-row)
                                :href course-href)
                          (list :text (notebook-title nb-row)))))
              (html-response
               (recurya/web/ui/notebook:render
                notebook
                :user user
                :saved-codes saved
                :passed-cells passed
                :sidebar-notebooks sidebar-notebooks
                :course-title (course-title course-row)
                :course-slug cs
                :course-handle course-handle
                :breadcrumb breadcrumb
                :course-prev-url prev-url
                :course-next-url next-url
                :noindex (not (string= (notebook-visibility nb-row) "public"))
                :run-cell-base run-cell-base))))
           (t
            (html-response
             (recurya/web/ui/notebook:render
              notebook
              :user user
              :saved-codes saved
              :passed-cells passed
              :sidebar-notebooks nil
              :noindex (not (string= (notebook-visibility nb-row) "public"))
              :run-cell-base run-cell-base)))))))))

(defun public-notebook-by-handle-handler (params)
  "Handle GET /@:handle/:slug - public single notebook page resolved by
the author's HANDLE plus the notebook SLUG. Owner sees drafts; others
see only published+public notebooks; everything else is 404.

Because Ningle/myway URL-encodes literal `@' in named-parameter
patterns, this handler is registered as a regex route in
`setup-routes'. Captured groups are extracted from the (:CAPTURES (...))
alist entry."
  (let* ((captures (get-path-param params :captures))
         (handle (and captures (first captures)))
         (slug (and captures (second captures)))
         (nb-row (find-notebook-by-handle-and-slug handle slug)))
    (%render-public-notebook-response nb-row params)))

(defun course-notebook-row->public-plist (cn)
  "Convert a course-notebook DAO into a plist for the public course view.

CN's underlying notebook is fetched via course-notebook-notebook
and projected into (:slug :title :summary :position :author-handle).
The :author-handle is needed so the course page can render
/@<handle>/<slug> links into each attached notebook."
  (let* ((nb (course-notebook-notebook cn))
         (author (and nb (notebook-author nb)))
         (author-handle
          (and author (recurya/models/users:users-handle author))))
    (list :slug (when nb (notebook-slug nb))
          :title (when nb (notebook-title nb))
          :summary (when nb (notebook-summary nb))
          :position (course-notebook-position cn)
          :author-handle author-handle)))

(defun %render-public-course-response (course-row)
  "Render the public course page for COURSE-ROW with access control.

Returns a Clack response list. Returns 404 when COURSE-ROW is NIL or
the viewer cannot view it."
  (let ((user (get-current-user)))
    (cond
      ((null course-row)
       (html-response (recurya/web/ui/errors:not-found) :status 404))
      ((not (recurya/utils/access-control:can-view-course-p user course-row))
       (html-response (recurya/web/ui/errors:not-found) :status 404))
      (t
       (let* ((rows (remove-if-not
                     (lambda (cn)
                       (let ((nb (course-notebook-notebook cn)))
                         (and nb
                              (recurya/utils/access-control:publicly-listable-notebook-p nb))))
                     (list-course-notebooks (course-id course-row))))
              (notebooks (mapcar #'course-notebook-row->public-plist rows)))
         (html-response
          (recurya/web/ui/course:render
           :course (course->plist course-row)
           :notebooks notebooks
           :user user
           :passed-by-notebook nil
           :noindex (not (string= (course-visibility course-row) "public")))))))))

(defun public-course-by-handle-handler (params)
  "Handle GET /c/@:handle/:slug - public single course page resolved by
author's HANDLE plus course SLUG.

Because Ningle/myway URL-encodes literal `@' in named-parameter
patterns, this handler is registered as a regex route in
`setup-routes'. Captured groups are extracted from (:CAPTURES (...))."
  (let* ((captures (get-path-param params :captures))
         (handle (and captures (first captures)))
         (slug (and captures (second captures)))
         (course-row (find-course-by-handle-and-slug handle slug)))
    (%render-public-course-response course-row)))

(defun profile-handler (params)
  "Handle GET /@:handle - user profile page listing the author's public
notebooks and courses. 404 when the handle does not resolve to a user.

Because Ningle/myway URL-encodes literal `@' in named-parameter
patterns, this handler is registered as a regex route in
`setup-routes'. The captured handle is the only group."
  (let* ((user (get-current-user))
         (captures (get-path-param params :captures))
         (handle (and captures (first captures)))
         (user-row (and handle (get-user-by-handle handle))))
    (cond
      ((null user-row)
       (html-response (recurya/web/ui/errors:not-found) :status 404))
      (t
       (html-response
        (render-profile-page
         :handle handle
         :display-name (recurya/models/users:users-display-name user-row)
         :notebooks (list-public-notebooks-of user-row)
         :courses (list-public-courses-of user-row)
         :user user))))))

(defun course-public-plist (c)
  "Convert a course DAO to a plist for the public listing UI.
Includes :author-handle so cards can link to /c/@<handle>/<slug> and
the @handle attribution badge."
  (let* ((author (course-author c))
         (author-name
          (when author (recurya/models/users:users-display-name author)))
         (author-handle
          (when author (recurya/models/users:users-handle author))))
    (list :slug (course-slug c)
          :title (course-title c)
          :summary (course-summary c)
          :published-at (course-published-at c)
          :author-name (or author-name "Anonymous")
          :author-handle author-handle
          :notebook-count (count-course-notebooks (course-id c)))))

(defun courses-public-handler (params)
  "Handle GET /courses - public listing of published courses.
No authentication required."
  (let* ((user (get-current-user))
         (page (parse-page-param params))
         (total-count (count-courses :status "published"
                                      :visibility "public"))
         (offset (* (1- page) *page-size*))
         (raw (list-courses :status "published"
                            :visibility "public"
                            :limit *page-size*
                            :offset offset))
         (courses (mapcar #'course-public-plist raw))
         (pagination
          (make-pagination page total-count *page-size* "/courses")))
    (html-response
     (recurya/web/ui/course-list:render :courses courses
                                        :pagination pagination
                                        :user user))))

(defun %maybe-persist-notebook-cell-run (uid nb-uuid cell result code)
  "Persist saved code, submission, and progress for a notebook cell run.
Anonymous users (UID NIL) are skipped silently; DB errors are logged but
do not poison the response."
  (when uid
    (handler-case
        (let* ((cell-id-str (string (or (cell-id cell) "")))
               (status      (notebook-cell-result-status result))
               (kind        (cell-kind cell))
               (status-str  (string-downcase (symbol-name status))))
          (upsert-cell-code uid nb-uuid cell-id-str (or code ""))
          (when (eq kind :code-exercise)
            (record-submission uid nb-uuid cell-id-str (or code "") status-str)
            (when (eq status :pass)
              (mark-cell-passed uid nb-uuid cell-id-str))))
      (error (e) (log:warn "Failed to persist notebook cell run: ~A" e)))))

(defun %run-public-cell (nb-row params)
  "Execute a cell on NB-ROW and render the HTMX result fragment.

Encapsulates the access check, index parsing, codes[] collection, and
optional persistence used by the handle-aware cell-run handler.

Returns a Clack response list. Returns 404 when NB-ROW is NIL or the
viewer cannot view it; 400 on bad index/cell-kind."
  (let* ((user (get-current-user))
         (uid (and user (getf user :id))))
    (cond
      ((null nb-row) (html-response "Notebook not found" :status 404))
      ((not (recurya/utils/access-control:can-view-notebook-p user nb-row))
       (html-response "Notebook not found" :status 404))
      (t
       (let* ((notebook (notebook-row->notebook-struct nb-row))
              (cells (notebook-cells notebook))
              (index-raw (get-path-param params :index))
              (index (typecase index-raw
                       (string (parse-integer index-raw :junk-allowed t))
                       (integer index-raw)
                       (t nil)))
              (codes-list (loop for (k . v) in params
                                when (and (stringp k) (string= k "codes[]"))
                                collect v)))
         (cond
           ((null index) (html-response "Invalid index" :status 400))
           ((or (< index 0) (>= index (length cells)))
            (html-response "Index out of range" :status 400))
           ((member (cell-kind (nth index cells))
                    '(:prose :code-solution))
            (html-response "Cannot run this cell" :status 400))
           (t
            (let* ((nb-uuid (princ-to-string (notebook-id nb-row)))
                   (result (run-cell notebook index codes-list))
                   (body (recurya/web/ui/notebook:render-cell-result result)))
              (%maybe-persist-notebook-cell-run
               uid nb-uuid (nth index cells) result (nth index codes-list))
              (html-response body)))))))))

(defun public-notebook-cell-run-by-handle-handler (params)
  "Handle POST /@:handle/:slug/cells/:index/run - HTMX fragment for
notebook cell execution resolved by the author's HANDLE plus the
notebook SLUG.

Because Ningle/myway URL-encodes literal `@' in named-parameter
patterns, this handler is registered as a regex route in
`setup-routes'. The (:CAPTURES (...)) alist entry holds the
HANDLE, SLUG, and INDEX in order. The handler synthesizes the
:slug and :index keys onto a copy of PARAMS so that the shared
`%run-public-cell' helper can read them via `get-path-param'."
  (let* ((captures (get-path-param params :captures))
         (handle (and captures (first captures)))
         (slug (and captures (second captures)))
         (index-str (and captures (third captures)))
         (nb-row (find-notebook-by-handle-and-slug handle slug))
         (params* (append (list (cons :slug slug)
                                (cons :index index-str))
                          params)))
    (%run-public-cell nb-row params*)))

(defun htmx-request-p ()
  "Return T if the current request was made by HTMX (HX-Request header present).
Checks both the Clack :headers hash-table (Hunchentoot) and the :http-hx-request
plist key (some Clack handlers normalize headers there)."
  (let* ((env (lack/request:request-env ningle/context:*request*))
         (headers (getf env :headers)))
    (or (getf env :http-hx-request)
        (and headers
             (gethash "hx-request" headers)))))

(defun render-confirm-modal (&key title message confirm-hx-post
                                   confirm-hx-target confirm-hx-swap
                                   confirm-label)
  "Render a confirmation modal overlay as an HTML fragment.
TITLE and MESSAGE describe the action. CONFIRM-HX-POST is the URL for the
confirm button's hx-post. CONFIRM-HX-TARGET and CONFIRM-HX-SWAP control
where the confirm response is swapped. CONFIRM-LABEL defaults to \"Delete\"."
  (let ((confirm-label (or confirm-label "Delete")))
    (spinneret:with-html-string
      (:div :class "modal-overlay"
            :role "dialog"
            :aria-modal "true"
            :hx-on\:click "if(event.target===this) htmx.find('#modal-container').innerHTML=''"
        (:div :class "modal-card"
          (:h3 title)
          (:p message)
          (:div :class "modal-actions"
            ;; Cancel: clear #modal-container innerHTML to remove the modal.
            ;; No server round-trip needed — hx-on:click runs client-side JS.
            (:button :type "button" :class "button-secondary"
                     :hx-on\:click "htmx.find('#modal-container').innerHTML=''"
                     "Cancel")
            ;; Confirm: POST to the action URL.  The response is swapped into
            ;; #modal-container (default), clearing the modal.  Handlers may
            ;; also include OOB swap elements to update other parts of the page.
            (:button :type "button" :class "button-danger"
                     :hx-post confirm-hx-post
                     :hx-target (or confirm-hx-target "#modal-container")
                     :hx-swap (or confirm-hx-swap "innerHTML")
                     :hx-include "#csrf-form"
                     confirm-label)))))))

;;; Account Handlers

(defun account-page-handler (params)
  "Handle GET /account - show account settings."
  (declare (ignore params))
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (html-response (recurya/web/ui/account:render :user user)))))

(defun account-update-handler (params)
  "Handle POST /account - update account settings."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let ((display-name (get-param params "display-name"))
              (language (get-param params "language"))
              (timezone (get-param params "timezone")))
          (if (or (null display-name) (string= (string-trim '(#\Space) display-name) ""))
              (redirect "/account?error=Display+name+cannot+be+blank")
              (progn
                (update-user! (getf user :id)
                              :display-name display-name
                              :language language
                              :timezone timezone)
                (setf (getf user :name) display-name)
                (setf (getf user :language) language)
                (setf (getf user :timezone) timezone)
                (set-session-user! user)
                (redirect "/account?message=Settings+updated")))))))

(defun account-confirm-delete-handler (params)
  "Handle GET /account/confirm-delete - return modal fragment for account deletion."
  (declare (ignore params))
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (html-response
         (render-confirm-modal
          :title "Delete your account?"
          :message "This will permanently delete your account and all associated posts. This action cannot be undone."
          :confirm-hx-post "/account/delete"
          :confirm-label "Delete account")))))

(defun account-delete-handler (params)
  "Handle POST /account/delete - delete account.
For HTMX requests, returns HX-Redirect header. For normal requests, redirects."
  (declare (ignore params))
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (progn
          (clear-session!)
          (if (htmx-request-p)
              ;; HTMX requests: use HX-Redirect header (not 302) because a
              ;; 302 redirect only applies to the AJAX sub-request — the
              ;; browser window wouldn't navigate.  HX-Redirect tells htmx.js
              ;; to set window.location, giving a full-page navigation.
              (list 200
                    (list :content-type "text/html; charset=utf-8"
                          :hx-redirect "/login")
                    (list ""))
              (redirect "/login"))))))

(defun onboarding-handle-page-handler (params)
  "Handle GET /onboarding/handle - show the handle setup form.

Behavior:
  * Anonymous users are redirected to /login.
  * Users whose handle is already a real (non-placeholder) handle are
    redirected to / (the dashboard / public landing).
  * Users with a placeholder handle (Phase 5 'u-XXXXXXXX') see the form."
  (declare (ignore params))
  (let ((session-user (get-current-user)))
    (cond
      ((null session-user)
       (redirect "/login"))
      ((not (placeholder-handle-p (getf session-user :handle)))
       (redirect "/"))
      (t
       (html-response
        (recurya/web/ui/onboarding:render-onboarding-handle-page
         :suggested-handle (getf session-user :handle)))))))

(defun onboarding-handle-create-handler (params)
  "Handle POST /onboarding/handle - validate and persist a new user-chosen handle.

Validation pipeline:
  1. session must contain a user, otherwise redirect to /login.
  2. trimmed/lowercased handle must satisfy
     RECURYA/UTILS/HANDLE:VALID-HANDLE-P (re-render with 400 on failure).
  3. handle must not be in RECURYA/UTILS/HANDLE:RESERVED-HANDLE-P (400).
  4. handle must be unique across users (409 if taken).
On success, persists the new handle on the USERS DAO, refreshes the
session plist, and redirects to /."
  (let* ((session-user (get-current-user))
         (raw (or (get-param params "handle") ""))
         (handle (string-downcase (string-trim '(#\Space #\Tab) raw))))
    (flet ((render-error (msg &key (status 400))
             (html-response
              (recurya/web/ui/onboarding:render-onboarding-handle-page
               :error msg
               :suggested-handle (if (zerop (length handle))
                                     (getf session-user :handle)
                                     handle))
              :status status)))
      (cond
        ((null session-user)
         (redirect "/login"))
        ((not (recurya/utils/handle:valid-handle-p handle))
         (render-error
          "Invalid handle. Use 3-64 lowercase letters, digits or hyphens, and start/end with a letter or digit."))
        ((recurya/utils/handle:reserved-handle-p handle)
         (render-error
          "That handle is reserved. Please choose a different one."))
        ((mito:find-dao 'recurya/models/users:users :handle handle)
         (render-error
          "That handle is already taken. Please choose a different one."
          :status 409))
        (t
         (let* ((user-id (getf session-user :id))
                (dao (mito:find-dao 'recurya/models/users:users :id user-id)))
           (cond
             ((null dao)
              (clear-session!)
              (redirect "/login"))
             (t
              (setf (recurya/models/users:users-handle dao) handle)
              (mito:save-dao dao)
              (set-session-user! (user-dao->plist dao))
              (redirect "/")))))))))

;;; Dynamic dispatch support for REPL-driven development

(defun %parse-sync-payload (raw-json)
  "Convert JSON payload {\"notebooks\":[{...}]} into the plist shape
   expected by recurya/db/learn:merge-localstorage. Tolerates missing or
   JSON-null fields (jzon decodes JSON null as the symbol NULL)."
  (let* ((parsed (parse-json raw-json))
         (notebooks (and (hash-table-p parsed) (gethash "notebooks" parsed))))
    (when (and notebooks (vectorp notebooks))
      (loop for nb across notebooks
            when (hash-table-p nb)
              collect (list :notebook-id (gethash "notebook_id" nb)
                            :passed
                            (let ((arr (gethash "passed" nb)))
                              (when (vectorp arr)
                                (loop for x across arr collect x)))
                            :codes
                            (let ((codes-ht (gethash "codes" nb)))
                              (when (hash-table-p codes-ht)
                                (let (acc)
                                  (maphash (lambda (k v) (push (cons k v) acc))
                                           codes-ht)
                                  acc))))))))

(defun learn-sync-handler (params)
  "POST /learn/sync — merge localStorage payload into DB.
   Auth required."
  (declare (ignore params))
  (let* ((session ningle/context:*session*)
         (user (and session (gethash :user session)))
         (uid (and user (getf user :id))))
    (cond
      ((null uid)
       (let ((h (make-hash-table :test 'equal)))
         (setf (gethash "error" h) "auth required")
         (json-response h :status 401)))
      (t
       (handler-case
           (let* ((raw (%read-request-body))
                  (notebooks (%parse-sync-payload raw))
                  (summary (merge-localstorage uid notebooks))
                  (out (make-hash-table :test 'equal)))
             (loop for (k v) on summary by #'cddr
                   do (setf (gethash (string-downcase (symbol-name k)) out) v))
             (json-response out))
         (error (e)
           (log:warn "Failed /learn/sync: ~A" e)
           (let ((h (make-hash-table :test 'equal)))
             (setf (gethash "error" h) "server error")
             (json-response h :status 500))))))))

(defparameter +sicp-author-handle+ "recurya"
  "Handle of the canonical SICP author user. The seed/setup process must
create this user (with a real human-friendly display-name) before the
wardlisp redirects can resolve. Phase 10 (T25) is responsible for
creating the seed user.")

(defun sicp-learn-redirect-handler (params)
  "GET /wardlisp/learn -> 301 /c/@<sicp-author>/sicp.
   Permanent redirect from the legacy SICP listing to the public course page."
  (declare (ignore params))
  (list 301
        (list :location (format nil "/c/@~A/sicp" +sicp-author-handle+))
        (list "")))

(defun sicp-notebook-redirect-handler (params)
  "GET /wardlisp/learn/:id -> 301 /@<sicp-author>/:id.
   Permanent redirect from the legacy notebook URL to the new
   handle-scoped public notebook URL. The :id path parameter is reused
   verbatim as the new slug."
  (let ((id (or (get-path-param params :slug)
                (get-path-param params :id))))
    (list 301
          (list :location (format nil "/@~A/~A"
                                  +sicp-author-handle+ (or id "")))
          (list ""))))

(defun sicp-cell-run-redirect-handler (params)
  "POST /wardlisp/learn/:id/cells/:index/run -> 308 /@<sicp-author>/:id/cells/:index/run.
   308 preserves the request method and body so HTMX POSTs are forwarded
   correctly to the new endpoint."
  (let ((id (or (get-path-param params :slug)
                (get-path-param params :id)))
        (index (get-path-param params :index)))
    (list 308
          (list :location (format nil "/@~A/~A/cells/~A/run"
                                  +sicp-author-handle+
                                  (or id "")
                                  (or index "")))
          (list ""))))

(defun learn-sync-redirect-handler (params)
  "POST /wardlisp/learn/sync -> 308 /learn/sync.
   308 preserves the POST method and body so existing browser localStorage
   sync clients keep working without changes."
  (declare (ignore params))
  (list 308 (list :location "/learn/sync") (list "")))

(defun make-dynamic-handler (handler-symbol)
  "Create a handler that looks up the function by symbol at call time.
This allows function redefinitions via SLIME to take effect immediately
without restarting the server."
  (lambda (params)
    (funcall (symbol-function handler-symbol) params)))

(defun not-found-handler (params)
  "Handle 404 - not found."
  (declare (ignore params))
  (html-response (recurya/web/ui/errors:not-found) :status 404))

(defun dashboard-home-handler (params)
  "GET /dashboard - redirect to /dashboard/notebooks (own notebooks list)."
  (declare (ignore params))
  (redirect "/dashboard/notebooks"))

;;; Route setup

(defun setup-routes (app)
  "Set up all routes on the Ningle application.
Uses dynamic dispatch to allow function redefinitions via SLIME to take effect
without restarting the server.

Note on `@'-prefixed routes:
Ningle/myway URL-encodes literal `@' in named-parameter patterns
(e.g. `/@:handle' compiles to a regex expecting `%40' instead of `@'),
so the @-handle routes are registered as regex routes (`:regexp t').
The captured groups arrive in the handler's PARAMS alist under
`:captures' as a list of strings, in pattern order."
  (setf (ningle/app:route app "/") (make-dynamic-handler 'root-handler))
  (setf (ningle/app:route app "/login")
          (make-dynamic-handler 'login-page-handler))
  (setf (ningle/app:route app "/logout" :method :post)
          (make-dynamic-handler 'logout-handler))
  (setf (ningle/app:route app "/auth/:provider/start")
          (make-dynamic-handler 'oauth-start-handler))
  (setf (ningle/app:route app "/auth/:provider/callback")
          (make-dynamic-handler 'oauth-callback-handler))
  (setf (ningle/app:route app "/dashboard")
          (make-dynamic-handler 'dashboard-home-handler))
  (setf (ningle/app:route app "/dashboard/notebooks")
          (make-dynamic-handler 'notebooks-handler))
  (setf (ningle/app:route app "/dashboard/notebooks/new")
          (make-dynamic-handler 'notebook-new-handler))
  (setf (ningle/app:route app "/dashboard/notebooks" :method :post)
          (make-dynamic-handler 'notebook-create-handler))
  (setf (ningle/app:route app "/dashboard/notebooks/:id/edit")
          (make-dynamic-handler 'notebook-edit-handler))
  (setf (ningle/app:route app "/dashboard/notebooks/:id" :method :post)
          (make-dynamic-handler 'notebook-update-handler))
  (setf (ningle/app:route app "/dashboard/notebooks/:id/state" :method :post)
          (make-dynamic-handler 'notebook-set-state-handler))
  (setf (ningle/app:route app "/dashboard/notebooks/:id/confirm-delete")
          (make-dynamic-handler 'notebook-confirm-delete-handler))
  (setf (ningle/app:route app "/dashboard/notebooks/:id/delete" :method :post)
          (make-dynamic-handler 'notebook-delete-handler))
  (setf (ningle/app:route app "/dashboard/courses")
          (make-dynamic-handler 'courses-me-handler))
  (setf (ningle/app:route app "/dashboard/courses/new")
          (make-dynamic-handler 'course-new-handler))
  (setf (ningle/app:route app "/dashboard/courses" :method :post)
          (make-dynamic-handler 'course-create-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id/edit")
          (make-dynamic-handler 'course-edit-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id" :method :post)
          (make-dynamic-handler 'course-update-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id/state" :method :post)
          (make-dynamic-handler 'course-set-state-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id/confirm-delete")
          (make-dynamic-handler 'course-confirm-delete-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id/delete" :method :post)
          (make-dynamic-handler 'course-delete-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id/notebooks" :method :post)
          (make-dynamic-handler 'course-add-notebook-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id/notebooks/:cn-id/up" :method :post)
          (make-dynamic-handler 'course-notebook-move-up-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id/notebooks/:cn-id/down" :method
                          :post)
          (make-dynamic-handler 'course-notebook-move-down-handler))
  (setf (ningle/app:route app "/dashboard/courses/:id/notebooks/:cn-id/remove" :method
                          :post)
          (make-dynamic-handler 'course-notebook-remove-handler))
  (setf (ningle/app:route app "/notebooks")
          (make-dynamic-handler 'notebooks-public-handler))
  ;; Public routes are @handle-scoped (regex-registered; see docstring).
  ;; Phase 7C removed the legacy slug-only paths /n/:slug, /c/:slug,
  ;; and /n/:slug/cells/:i/run; their successors live under /@:handle/...
  (setf (ningle/app:route app "^/@([\\w-]+)/?$"
                          :method :get :regexp t)
          (make-dynamic-handler 'profile-handler))
  (setf (ningle/app:route app "^/@([\\w-]+)/([\\w-]+)/?$"
                          :method :get :regexp t)
          (make-dynamic-handler 'public-notebook-by-handle-handler))
  (setf (ningle/app:route app "^/@([\\w-]+)/([\\w-]+)/cells/(\\d+)/run$"
                          :method :post :regexp t)
          (make-dynamic-handler 'public-notebook-cell-run-by-handle-handler))
  (setf (ningle/app:route app "^/c/@([\\w-]+)/([\\w-]+)/?$"
                          :method :get :regexp t)
          (make-dynamic-handler 'public-course-by-handle-handler))
  (setf (ningle/app:route app "/courses")
          (make-dynamic-handler 'courses-public-handler))
  (setf (ningle/app:route app "/onboarding/handle")
          (make-dynamic-handler 'onboarding-handle-page-handler))
  (setf (ningle/app:route app "/onboarding/handle" :method :post)
          (make-dynamic-handler 'onboarding-handle-create-handler))
  (setf (ningle/app:route app "/account")
          (make-dynamic-handler 'account-page-handler))
  (setf (ningle/app:route app "/account" :method :post)
          (make-dynamic-handler 'account-update-handler))
  (setf (ningle/app:route app "/account/confirm-delete")
          (make-dynamic-handler 'account-confirm-delete-handler))
  (setf (ningle/app:route app "/account/delete" :method :post)
          (make-dynamic-handler 'account-delete-handler))
  (setf (ningle/app:route app "/learn/sync" :method :post)
          (make-dynamic-handler 'learn-sync-handler))
  app)
