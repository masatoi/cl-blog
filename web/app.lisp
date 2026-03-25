;;;; web/app.lisp --- Ningle application instance and initialization.
;;;;
;;;; Creates the Ningle app, wires routes via setup-routes, and exports
;;;; *app* for use by the server and middleware layers.

(defpackage #:recurya/web/app
  (:use #:cl)
  (:import-from #:recurya/web/routes-wardlisp
                #:setup-wardlisp-routes)
  (:export #:*app*
           #:make-recurya-app))

(in-package #:recurya/web/app)

(defvar *app* nil
  "The Ningle application instance.")

(defun make-recurya-app ()
  "Create and return a new Ningle application."
  (setf *app* (make-instance 'ningle:app))
  (setup-wardlisp-routes *app*)
  *app*)
