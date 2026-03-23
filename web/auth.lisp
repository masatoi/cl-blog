(defpackage #:cl-blog/web/auth
  (:use #:cl)
  (:import-from #:cl-blog/db/users
                #:get-user-by-email
                #:create-user!)
  (:import-from #:ironclad
                #:make-digest
                #:update-digest
                #:produce-digest
                #:random-data
                #:byte-array-to-hex-string
                #:hex-string-to-byte-array)
  (:import-from #:babel
                #:string-to-octets)
  (:export #:derive-password
           #:verify-password
           #:authenticate
           #:register!
           #:email-exists-p
           #:ensure-default-admin!))

(in-package #:cl-blog/web/auth)

;;; Password hashing using SHA-256 with salt

(defun random-salt ()
  "Generate 16 random bytes as salt."
  (ironclad:random-data 16))

(defun sha256 (salt password)
  "Compute SHA-256 hash of salt + password."
  (let ((digest (ironclad:make-digest :sha256)))
    (ironclad:update-digest digest salt)
    (ironclad:update-digest digest (babel:string-to-octets password :encoding :utf-8))
    (ironclad:produce-digest digest)))

(declaim (ftype (function (string) list) derive-password))
(defun derive-password (password)
  "Generate a salted SHA-256 password hash.

Arguments:
  PASSWORD - Plain text password string

Returns:
  A plist with :SALT and :HASH as hex strings."
  (let* ((salt (random-salt))
         (hash (sha256 salt password)))
    (list :salt (ironclad:byte-array-to-hex-string salt)
          :hash (ironclad:byte-array-to-hex-string hash))))

(declaim (ftype (function (string (or string null) (or string null)) boolean) verify-password))
(defun verify-password (password salt-hex hash-hex)
  "Verify a password against stored salt and hash (both hex strings).

Arguments:
  PASSWORD - Plain text password to verify
  SALT-HEX - Hex-encoded salt string
  HASH-HEX - Hex-encoded hash string

Returns:
  T if password matches, NIL otherwise."
  (when (and salt-hex hash-hex)
    (let* ((salt (ironclad:hex-string-to-byte-array salt-hex))
           (computed-hash (sha256 salt password))
           (computed-hex (ironclad:byte-array-to-hex-string computed-hash)))
      (string= computed-hex hash-hex))))

;;; User authentication

(declaim (ftype (function (string) boolean) email-exists-p))
(defun email-exists-p (email)
  "Check if a user with the given email exists.

Arguments:
  EMAIL - Email address to check

Returns:
  T if user exists, NIL otherwise."
  (let ((normalized (string-downcase (string-trim '(#\Space #\Tab) email))))
    (not (null (get-user-by-email normalized)))))

(declaim (ftype (function (string string) (or list null)) authenticate))
(defun authenticate (email password)
  "Authenticate a user by email and password.

Arguments:
  EMAIL    - User's email address
  PASSWORD - Plain text password

Returns:
  A plist (:id :email :name :role) on success, NIL on failure."
  (let* ((normalized-email (string-downcase (string-trim '(#\Space #\Tab) email)))
         (user (get-user-by-email normalized-email)))
    (when (and user
               (verify-password password
                                (cl-blog/db/users:users-password-salt user)
                                (cl-blog/db/users:users-password-hash user)))
      (list :id (cl-blog/db/users:users-id user)
            :email (cl-blog/db/users:users-email user)
            :name (cl-blog/db/users:users-display-name user)
            :role (intern (string-upcase (cl-blog/db/users:users-role user)) :keyword)
            :language (cl-blog/db/users:users-language user)
            :timezone (cl-blog/db/users:users-timezone user)))))

(declaim (ftype (function (&key (:email (or string null))
                                (:password (or string null))
                                (:name (or string null))
                                (:role t))
                          list)
                register!))
(defun register! (&key email password name role)
  "Register a new user.

Arguments:
  EMAIL    - User's email address (required)
  PASSWORD - Plain text password (required)
  NAME     - Display name (required)
  ROLE     - User role keyword (optional, default: :USER)

Returns:
  (:ok user-plist) on success, (:error reason) on failure.
  Possible error reasons: :email/blank, :password/blank, :name/blank, :email/exists."
  (let ((email (and email (string-downcase (string-trim '(#\Space #\Tab) email)))))
    (cond
      ((or (null email) (string= email ""))
       (list :error :email/blank))
      ((or (null password) (string= password ""))
       (list :error :password/blank))
      ((or (null name) (string= name ""))
       (list :error :name/blank))
      ((email-exists-p email)
       (list :error :email/exists))
      (t
       (let* ((derived (derive-password password))
              (user (create-user!
                     :email email
                     :display-name name
                     :password-hash (getf derived :hash)
                     :password-salt (getf derived :salt)
                     :role (or (and role (string-downcase (string role))) "user"))))
         (list :ok (list :id (cl-blog/db/users:users-id user)
                         :email (cl-blog/db/users:users-email user)
                         :name (cl-blog/db/users:users-display-name user)
                         :role (intern (string-upcase (cl-blog/db/users:users-role user)) :keyword)
                         :language (cl-blog/db/users:users-language user)
                         :timezone (cl-blog/db/users:users-timezone user))))))))

(declaim (ftype (function () (or list null)) ensure-default-admin!))
(defun ensure-default-admin! ()
  "Create the default admin user if it doesn't exist.

Returns:
  Registration result if user was created, NIL if already exists.

Side Effects:
  Creates admin@cl-blog.dev user with password 'changeme'."
  (let ((email "admin@cl-blog.dev"))
    (unless (email-exists-p email)
      (register! :email email
                 :password "changeme"
                 :name "Administrator"
                 :role :admin))))

(defun current-user (env)
  "Extract the current user from the Lack session in ENV."
  (let ((session (getf env :lack.session)))
    (when session
      (gethash :user session))))
