;;;; db/users.lisp --- CRUD operations for the users table.
;;;;
;;;; Provides create, read, update, delete, and listing for users.
;;;; Uses Mito ORM (select-dao, insert-dao) with the users deftable
;;;; defined in models/users.lisp.

(defpackage #:recurya/db/users
  (:use #:cl)
  (:import-from #:mito
                #:find-dao
                #:select-dao
                #:insert-dao
                #:save-dao
                #:delete-dao)
  (:import-from #:sxql
                #:order-by)
  (:import-from #:recurya/db/core
                #:generate-uuid)
  ;; Import users class and accessors from models
  (:import-from #:recurya/models/users
                #:users
                #:users-id
                #:users-email
                #:users-password-hash
                #:users-password-salt
                #:users-display-name
                #:users-role
                #:users-language
                #:users-timezone
                #:users-created-at
                #:users-updated-at)
  (:export
   ;; Re-export the Mito class and accessors
   #:users
   #:users-id
   #:users-email
   #:users-password-hash
   #:users-password-salt
   #:users-display-name
   #:users-role
   #:users-language
   #:users-timezone
   #:users-created-at
   #:users-updated-at
   ;; CRUD operations
   #:create-user!
   #:get-user-by-id
   #:get-user-by-email
   #:update-user!
   #:delete-user!
   #:list-users))

(in-package #:recurya/db/users)

;;; ============================================================
;;; CRUD Operations using Mito DAO
;;; ============================================================

(defun create-user! (&key email password-hash password-salt display-name (role "user"))
  "Create a new user and return the created user instance.

Arguments:
  EMAIL         - User's email address (required, must be unique)
  PASSWORD-HASH - Pre-computed password hash (required)
  PASSWORD-SALT - Salt used for hashing (required)
  DISPLAY-NAME  - Optional display name
  ROLE          - User role (default: \"user\")

Returns:
  The newly created USER instance.

Side Effects:
  Inserts a new row into the users table with auto-generated UUID.
  Mito automatically sets created_at and updated_at timestamps."
  (let ((user-id (generate-uuid)))
    (insert-dao (make-instance 'users
                               :id user-id
                               :email email
                               :password-hash password-hash
                               :password-salt password-salt
                               :display-name display-name
                               :role role))))

(defun get-user-by-id (user-id)
  "Fetch a user by their unique ID.

Arguments:
  USER-ID - UUID string.

Returns:
  USER instance if found, NIL otherwise."
  (find-dao 'users :id user-id))

(defun get-user-by-email (email)
  "Fetch a user by their email address.

Arguments:
  EMAIL - Email address string.

Returns:
  USER instance if found, NIL otherwise.

Note: Email lookup is case-sensitive."
  (find-dao 'users :email email))

(defun update-user! (user-id &key password-hash password-salt display-name role
                              language timezone)
  "Update user attributes. Only provided fields are updated.

Arguments:
  USER-ID       - UUID of the user to update
  PASSWORD-HASH - New password hash (optional)
  PASSWORD-SALT - New password salt (optional)
  DISPLAY-NAME  - New display name (optional)
  ROLE          - New role (optional)
  LANGUAGE      - Preferred language code, e.g. \"en\", \"ja\" (optional)
  TIMEZONE      - Preferred timezone, e.g. \"Asia/Tokyo\" (optional)

Returns:
  The updated USER instance.

Side Effects:
  Updates the specified fields. Mito automatically updates updated_at."
  (let ((user (find-dao 'users :id user-id)))
    (when user
      (when password-hash
        (setf (users-password-hash user) password-hash))
      (when password-salt
        (setf (users-password-salt user) password-salt))
      (when display-name
        (setf (users-display-name user) display-name))
      (when role
        (setf (users-role user) role))
      (when language
        (setf (users-language user) language))
      (when timezone
        (setf (users-timezone user) timezone))
      (save-dao user))
    user))

(defun delete-user! (email)
  "Delete a user by email address.

Arguments:
  EMAIL - Email address of the user to delete.

Returns:
  T if a user was deleted, NIL if no user with that email existed."
  (let ((user (find-dao 'users :email email)))
    (when user
      (delete-dao user)
      t)))

(defun list-users ()
  "List all users ordered by creation date (newest first).

Returns:
  List of USER instances.

Note: For production use, consider pagination for large user bases."
  (select-dao 'users (order-by (:desc :created-at))))
