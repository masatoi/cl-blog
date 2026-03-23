;;;; web/app.lisp --- Ningle application instance and initialization.
;;;;
;;;; Creates the Ningle app, wires routes via setup-routes, and exports
;;;; *app* for use by the server and middleware layers.

(defpackage #:cl-blog/web/app
  (:use #:cl)
  (:export #:*app*
           #:make-cl-blog-app))

(in-package #:cl-blog/web/app)

(defvar *app* nil
  "The Ningle application instance.")

(defun make-cl-blog-app ()
  "Create and return a new Ningle application."
  (setf *app* (make-instance 'ningle:app))
  *app*)
