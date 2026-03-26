;;;; models/users.lisp --- Mito ORM table definition for the users table.
;;;;
;;;; Defines the `users` table schema with UUID primary key, email,
;;;; password hash/salt, display name, role, and regional preferences.
;;;; Accessor functions are exported for use by the DB and web layers.

(defpackage #:recurya/models/users
  (:use #:cl
        #:mito)
  (:export #:users
           #:users-id
           #:users-email
           #:users-password-hash
           #:users-password-salt
           #:users-display-name
           #:users-role
           #:users-language
           #:users-timezone
           #:users-created-at
           #:users-updated-at))

(in-package #:recurya/models/users)

(deftable users ()
  ((id :col-type :uuid
       :initarg :id
       :accessor %users-id
       :primary-key t)
   (email :col-type (:varchar 255)
          :initarg :email
          :accessor users-email)
   (password-hash :col-type (:varchar 255)
                  :initarg :password-hash
                  :accessor users-password-hash)
   (password-salt :col-type (:varchar 255)
                  :initarg :password-salt
                  :accessor users-password-salt)
   (display-name :col-type (:varchar 255)
                 :initarg :display-name
                 :accessor users-display-name)
   (role :col-type (:varchar 64)
         :initarg :role
         :initform "user"
         :accessor users-role)
   (language :col-type (or (:varchar 16) :null)
             :initarg :language
             :initform "en"
             :accessor users-language)
   (timezone :col-type (or (:varchar 64) :null)
             :initarg :timezone
             :initform "UTC"
             :accessor users-timezone))
  ;; Disable Mito's auto-generated integer PK; we use an explicit UUID column.
  (:auto-pk nil)
  (:unique-keys email)
  (:documentation "User account with authentication credentials and preferences."))

(defun users-id (user)
  "Return the UUID primary key for USER."
  (%users-id user))

(defun users-created-at (user)
  "Return the creation timestamp for USER."
  (mito:object-created-at user))

(defun users-updated-at (user)
  "Return the last-updated timestamp for USER."
  (mito:object-updated-at user))
