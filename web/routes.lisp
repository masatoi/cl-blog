(defpackage #:cl-blog/web/routes
  (:use #:cl)
  (:import-from #:cl-blog/web/auth
                #:authenticate
                #:register!)
  (:import-from #:cl-blog/db/users
                #:update-user!
                #:get-user-by-id)
  (:import-from #:cl-blog/web/ui/login)
  (:import-from #:cl-blog/web/ui/signup)
  (:import-from #:cl-blog/web/ui/errors)
  (:import-from #:cl-blog/web/ui/account)
  (:import-from #:cl-blog/web/ui/posts)
  (:import-from #:cl-blog/web/ui/post-form)
  (:import-from #:cl-blog/web/ui/blog)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:lack/request
                #:request-env)
  (:import-from #:cl-blog/web/ui/blog-post)
  (:import-from #:cl-blog/db/posts
                #:create-post!
                #:get-post-by-id
                #:get-post-by-slug
                #:update-post!
                #:delete-post!
                #:list-posts
                #:count-posts
                #:slugify
                #:post-id
                #:post-title
                #:post-slug
                #:post-body
                #:post-excerpt
                #:post-status
                #:post-published-at
                #:post-author
                #:post-author-id
                #:post-created-at
                #:post-updated-at)
  (:export #:setup-routes
           #:account-confirm-delete-handler
           #:account-delete-handler
           #:post-confirm-delete-handler
           #:post-delete-handler))


(in-package #:cl-blog/web/routes)

;;; Response helpers

(defun html-response (body &key (status 200))
  "Create an HTML response."
  (list status '(:content-type "text/html; charset=utf-8") (list body)))

(defun redirect (location)
  "Create a redirect response."
  (list 302 (list :location location) (list "")))

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
  "Handle / - redirect to posts or login."
  (declare (ignore params))
  (if (get-current-user)
      (redirect "/posts")
      (redirect "/login")))

(defun login-page-handler (params)
  "Handle GET /login - show login form."
  (declare (ignore params))
  (if (get-current-user)
      (redirect "/posts")
      (html-response (cl-blog/web/ui/login:render))))

(defun login-handler (params)
  "Handle POST /login - authenticate user."
  (let* ((email (get-param params "email"))
         (password (get-param params "password"))
         (user (authenticate email password)))
    (if user
        (progn
          (set-session-user! user)
          (redirect "/posts"))
        (html-response (cl-blog/web/ui/login:render :error "Invalid email or password.")
                       :status 401))))

(defun logout-handler (params)
  "Handle POST /logout - clear session."
  (declare (ignore params))
  (clear-session!)
  (redirect "/login"))

(defun signup-page-handler (params)
  "Handle GET /signup - show signup form."
  (declare (ignore params))
  (if (get-current-user)
      (redirect "/posts")
      (html-response (cl-blog/web/ui/signup:render))))

(defun signup-handler (params)
  "Handle POST /signup - register new user."
  (let* ((email (get-param params "email"))
         (password (get-param params "password"))
         (name (get-param params "name"))
         (result (register! :email email :password password :name name)))
    (if (getf result :ok)
        (let ((user (getf result :ok)))
          (set-session-user! user)
          (redirect "/posts"))
        (let ((error-key (getf result :error)))
          (html-response (cl-blog/web/ui/signup:render
                          :error (princ-to-string error-key))
                         :status 400)))))

;;; Blog Post Handlers

(defun post->plist (p)
  "Convert a post instance to a plist for UI rendering.
Includes :author-name extracted from the FK author."
  (let* ((author (post-author p))
         (author-name (when author
                        (cl-blog/models/users:users-display-name author))))
    (list :id (post-id p)
          :title (post-title p)
          :slug (post-slug p)
          :body (post-body p)
          :excerpt (post-excerpt p)
          :status (post-status p)
          :published-at (post-published-at p)
          :created-at (post-created-at p)
          :updated-at (post-updated-at p)
          :author-name (or author-name "Anonymous"))))

(defun get-session-user-object ()
  "Get the current user as a Mito DAO object for FK references."
  (let ((user (get-current-user)))
    (when user
      (let ((user-id (getf user :id)))
        (when user-id
          (get-user-by-id user-id))))))

(defun posts-handler (params)
  "Handle GET /posts - admin post list with pagination (user's own posts only)."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((user-id (getf user :id))
               (page (parse-page-param params))
               (total-count (count-posts :author-id user-id))
               (offset (* (1- page) *page-size*))
               (posts-raw (list-posts :author-id user-id
                                      :limit *page-size* :offset offset))
               (posts (mapcar #'post->plist posts-raw))
               (pagination (make-pagination page total-count *page-size* "/posts")))
          (html-response
           (cl-blog/web/ui/posts:render :user user :posts posts
                                           :pagination pagination))))))

(defun post-new-handler (params)
  "Handle GET /posts/new - show new post form."
  (declare (ignore params))
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (html-response
         (cl-blog/web/ui/post-form:render :user user)))))

(defun post-create-handler (params)
  "Handle POST /posts - create a new post."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let ((title (get-param params "title"))
              (slug (get-param params "slug"))
              (body (get-param params "body"))
              (excerpt (get-param params "excerpt"))
              (status (get-param params "status")))
          (cond
            ((or (null title) (equal title ""))
             (html-response
              (cl-blog/web/ui/post-form:render :user user
                                                  :errors '("Title is required."))))
            ((or (null body) (equal body ""))
             (html-response
              (cl-blog/web/ui/post-form:render :user user
                                                  :errors '("Body is required.")
                                                  :post (list :title title :slug slug
                                                              :excerpt excerpt :status status))))
            (t
             (let* ((slug-val (if (and slug (string/= slug "")) slug nil))
                    (excerpt-val (if (and excerpt (string/= excerpt "")) excerpt nil))
                    (published-at (when (equal status "published") (local-time:now)))
                    (post (create-post! :title title
                                        :slug slug-val
                                        :body body
                                        :excerpt excerpt-val
                                        :status (or status "draft")
                                        :published-at published-at
                                        :author (get-session-user-object))))
               (declare (ignore post))
               (redirect "/posts"))))))))

(defun post-edit-handler (params)
  "Handle GET /posts/:id/edit - show edit form for existing post (owner only)."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (post (get-post-by-id id)))
          (cond
            ((null post)
             (html-response (cl-blog/web/ui/errors:not-found) :status 404))
            ((not (equal (princ-to-string (post-author-id post))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (html-response
              (cl-blog/web/ui/post-form:render :user user
                                                  :post (post->plist post)))))))))

(defun post-update-handler (params)
  "Handle POST /posts/:id - update an existing post (owner only)."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (existing (get-post-by-id id)))
          (cond
            ((null existing)
             (html-response (cl-blog/web/ui/errors:not-found) :status 404))
            ((not (equal (princ-to-string (post-author-id existing))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let ((title (get-param params "title"))
                   (slug (get-param params "slug"))
                   (body (get-param params "body"))
                   (excerpt (get-param params "excerpt"))
                   (status (get-param params "status")))
               (cond
                 ((or (null title) (equal title ""))
                  (html-response
                   (cl-blog/web/ui/post-form:render
                    :user user
                    :post (post->plist existing)
                    :errors '("Title is required."))))
                 ((or (null body) (equal body ""))
                  (html-response
                   (cl-blog/web/ui/post-form:render
                    :user user
                    :post (list :id id :title title :slug slug
                                :excerpt excerpt :status status)
                    :errors '("Body is required."))))
                 (t
                  (let* ((slug-val (if (and slug (string/= slug "")) slug nil))
                         (excerpt-val (if (and excerpt (string/= excerpt "")) excerpt nil))
                         (published-at
                          (when (and (equal status "published")
                                     (not (equal (post-status existing) "published")))
                            (local-time:now))))
                    (update-post! id
                                  :title title
                                  :slug slug-val
                                  :body body
                                  :excerpt excerpt-val
                                  :status (or status "draft")
                                  :published-at published-at)
                    (redirect "/posts")))))))))))

(defun htmx-request-p ()
  "Return T if the current request was made by HTMX (HX-Request header present).
Checks both the Clack :headers hash-table (Hunchentoot) and the :http-hx-request
plist key (some Clack handlers normalize headers there)."
  (let* ((env (lack/request:request-env ningle/context:*request*))
         (headers (getf env :headers)))
    (or (getf env :http-hx-request)
        (and headers
             (gethash "hx-request" headers)))))

(defun render-status-pill (id status)
  "Render a status pill HTML fragment for HTMX swap.
ID is the post UUID, STATUS is the current status string."
  (let ((status-lower (string-downcase (or status "draft"))))
    (spinneret:with-html-string
      (:span :class "status-pill"
       :id (format nil "status-~A" id)
       :data-status status-lower
       :hx-post (format nil "/posts/~A/toggle-status" id)
       :hx-target (format nil "#status-~A" id)
       :hx-swap "outerHTML"
       (string-capitalize status-lower)))))

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
            (:button :type "button" :class "button-secondary"
                     :hx-on\:click "htmx.find('#modal-container').innerHTML=''"
                     "Cancel")
            (:button :type "button" :class "button-danger"
                     :hx-post confirm-hx-post
                     :hx-target (or confirm-hx-target "#modal-container")
                     :hx-swap (or confirm-hx-swap "innerHTML")
                     confirm-label)))))))

(defun post-toggle-status-handler (params)
  "Handle POST /posts/:id/toggle-status - toggle between draft and published (HTMX).
Returns the updated status pill HTML fragment."
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (let* ((id (get-path-param params :id))
               (post (get-post-by-id id)))
          (cond
            ((null post)
             (html-response "Not found" :status 404))
            ((not (equal (princ-to-string (post-author-id post))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (let* ((current-status (post-status post))
                    (new-status (if (equal current-status "published") "draft" "published"))
                    (published-at (when (equal new-status "published") (local-time:now))))
               (update-post! id :status new-status
                                :published-at published-at)
               (html-response (render-status-pill id new-status)))))))))

(defun post-confirm-delete-handler (params)
  "Handle GET /posts/:id/confirm-delete - return modal fragment for post deletion.
Auth + ownership check, then renders a confirmation modal with HTMX attributes."
  (let ((user (get-current-user)))
    (if (null user)
        (html-response "Unauthorized" :status 401)
        (let* ((id (get-path-param params :id))
               (post (get-post-by-id id)))
          (cond
            ((null post)
             (html-response "Not found" :status 404))
            ((not (equal (princ-to-string (post-author-id post))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (html-response
              (render-confirm-modal
               :title "Delete this post?"
               :message (format nil "\"~A\" will be permanently deleted. This cannot be undone."
                                (post-title post))
               :confirm-hx-post (format nil "/posts/~A/delete" id)
               :confirm-label "Delete post"))))))))

(defun post-delete-handler (params)
  "Handle POST /posts/:id/delete - delete a post (owner only).
Returns empty HTML for HTMX requests (row removal), or redirects for normal requests."
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let* ((id (get-path-param params :id))
               (post (get-post-by-id id)))
          (cond
            ((null post)
             (html-response (cl-blog/web/ui/errors:not-found) :status 404))
            ((not (equal (princ-to-string (post-author-id post))
                         (princ-to-string (getf user :id))))
             (html-response "Forbidden" :status 403))
            (t
             (delete-post! id)
             (if (htmx-request-p)
                 (html-response
                  (spinneret:with-html-string
                    (:tr :id (format nil "post-row-~A" id)
                         :hx-swap-oob "outerHTML")))
                 (redirect "/posts"))))))))

(defun blog-handler (params)
  "Handle GET /blog - public blog listing (published posts only)."
  (let* ((page (parse-page-param params))
         (total-count (count-posts :status "published"))
         (offset (* (1- page) *page-size*))
         (posts-raw (list-posts :status "published" :limit *page-size* :offset offset))
         (posts (mapcar #'post->plist posts-raw))
         (pagination (make-pagination page total-count *page-size* "/blog")))
    (html-response
     (cl-blog/web/ui/blog:render :posts posts :pagination pagination))))

(defun blog-post-handler (params)
  "Handle GET /blog/:slug - public single post view."
  (let* ((slug (get-path-param params :slug))
         (post (get-post-by-slug slug)))
    (if (or (null post) (not (equal (post-status post) "published")))
        (html-response (cl-blog/web/ui/blog-post:render :post nil) :status 404)
        (html-response
         (cl-blog/web/ui/blog-post:render :post (post->plist post))))))

;;; Account Handlers

(defun account-page-handler (params)
  "Handle GET /account - show account settings."
  (declare (ignore params))
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (html-response (cl-blog/web/ui/account:render :user user)))))

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
              (list 200
                    (list :content-type "text/html; charset=utf-8"
                          :hx-redirect "/login")
                    (list ""))
              (redirect "/login"))))))

;;; Dynamic dispatch support for REPL-driven development

(defun make-dynamic-handler (handler-symbol)
  "Create a handler that looks up the function by symbol at call time.
This allows function redefinitions via SLIME to take effect immediately
without restarting the server."
  (lambda (params)
    (funcall (symbol-function handler-symbol) params)))

(defun not-found-handler (params)
  "Handle 404 - not found."
  (declare (ignore params))
  (html-response (cl-blog/web/ui/errors:not-found) :status 404))

;;; Route setup

(defun setup-routes (app)
  "Set up all routes on the Ningle application.
Uses dynamic dispatch to allow function redefinitions via SLIME to take effect
without restarting the server."
  (setf (ningle/app:route app "/") (make-dynamic-handler 'root-handler))
  (setf (ningle/app:route app "/login")
          (make-dynamic-handler 'login-page-handler))
  (setf (ningle/app:route app "/login" :method :post)
          (make-dynamic-handler 'login-handler))
  (setf (ningle/app:route app "/logout" :method :post)
          (make-dynamic-handler 'logout-handler))
  (setf (ningle/app:route app "/signup")
          (make-dynamic-handler 'signup-page-handler))
  (setf (ningle/app:route app "/signup" :method :post)
          (make-dynamic-handler 'signup-handler))
  ;; Blog admin routes (auth required)
  (setf (ningle/app:route app "/posts")
          (make-dynamic-handler 'posts-handler))
  (setf (ningle/app:route app "/posts/new")
          (make-dynamic-handler 'post-new-handler))
  (setf (ningle/app:route app "/posts" :method :post)
          (make-dynamic-handler 'post-create-handler))
  (setf (ningle/app:route app "/posts/:id/edit")
          (make-dynamic-handler 'post-edit-handler))
  (setf (ningle/app:route app "/posts/:id" :method :post)
          (make-dynamic-handler 'post-update-handler))
  (setf (ningle/app:route app "/posts/:id/toggle-status" :method :post)
          (make-dynamic-handler 'post-toggle-status-handler))
  (setf (ningle/app:route app "/posts/:id/confirm-delete")
          (make-dynamic-handler 'post-confirm-delete-handler))
  (setf (ningle/app:route app "/posts/:id/delete" :method :post)
          (make-dynamic-handler 'post-delete-handler))
  ;; Public blog routes (no auth)
  (setf (ningle/app:route app "/blog")
          (make-dynamic-handler 'blog-handler))
  (setf (ningle/app:route app "/blog/:slug")
          (make-dynamic-handler 'blog-post-handler))
  ;; Account management
  (setf (ningle/app:route app "/account")
          (make-dynamic-handler 'account-page-handler))
  (setf (ningle/app:route app "/account" :method :post)
          (make-dynamic-handler 'account-update-handler))
  (setf (ningle/app:route app "/account/confirm-delete")
          (make-dynamic-handler 'account-confirm-delete-handler))
  (setf (ningle/app:route app "/account/delete" :method :post)
          (make-dynamic-handler 'account-delete-handler))
  app)
