;;;; db.lisp --- Aggregate package re-exporting all DB layer symbols.

(defpackage #:cl-blog/db
  (:use #:cl)
  (:documentation "Database access facade. All database operations are delegated to specialized modules.")
  ;; Re-export from core
  (:import-from #:cl-blog/db/core
                #:start!
                #:stop!
                #:datasource
                #:with-transaction)
  ;; Re-export from users
  (:import-from #:cl-blog/db/users
                #:create-user!
                #:get-user-by-id
                #:get-user-by-email
                #:update-user!
                #:delete-user!
                #:list-users)
  ;; Re-export from posts
  (:import-from #:cl-blog/db/posts
                #:create-post!
                #:get-post-by-id
                #:get-post-by-slug
                #:update-post!
                #:delete-post!
                #:list-posts
                #:count-posts)
  (:export
   ;; Core database management
   #:start!
   #:stop!
   #:datasource
   #:with-transaction

   ;; Users
   #:create-user!
   #:get-user-by-id
   #:get-user-by-email
   #:update-user!
   #:delete-user!
   #:list-users

   ;; Posts
   #:create-post!
   #:get-post-by-id
   #:get-post-by-slug
   #:update-post!
   #:delete-post!
   #:list-posts
   #:count-posts))

(in-package #:cl-blog/db)

;; This package serves as a facade, re-exporting all database operations
;; from specialized modules. No additional code needed here.
