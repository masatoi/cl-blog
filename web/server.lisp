;;;; web/server.lisp --- Clack/Hunchentoot HTTP server lifecycle.
;;;;
;;;; Provides start!/stop! for the Hunchentoot-backed web server.
;;;; The Lack application is built in build-app with session and
;;;; backtrace middleware (see web/app.lisp for the Ningle app).

(defpackage #:recurya/web/server
  (:use #:cl)
  (:import-from #:clack
                #:clackup
                #:stop)
  (:import-from #:recurya/web/app
                #:make-recurya-app)
  (:import-from #:recurya/web/routes
                #:setup-routes)
  (:import-from #:recurya/web/auth
                #:ensure-default-admin!)
  (:export #:start!
           #:stop!
           #:*handler*))

(in-package #:recurya/web/server)

(defvar *handler* nil
  "The Clack handler for the running server.")

(defparameter *default-port* 3000
  "Default port for the web server.")

(defun get-port ()
  "Get the server port from environment or use default."
  (let ((port-str (uiop:getenv "PORT")))
    (if port-str
        (parse-integer port-str :junk-allowed t)
        *default-port*)))

(defun build-app ()
  "Build the complete Lack application with middleware."
  (let ((app (make-recurya-app)))
    (setup-routes app)
    ;; Lack middleware stack (outermost listed first):
    ;; 1. :session  — cookie-based session (provides ningle/context:*session*)
    ;; 2. :backtrace — renders a debug backtrace page on unhandled errors
    ;; 3. app       — the Ningle router with all route handlers
    (lack/builder:builder
     :session
     :backtrace
     app)))

(defun start! (&key (port nil) (address "0.0.0.0"))
  "Start the web server.

   Options:
   - :port    - Port to listen on (default: 3000 or PORT env var)
   - :address - Address to bind to (default: 0.0.0.0 for all interfaces)"
  (when *handler*
    (log:info "Server already running, stopping first...")
    (stop!))

  (let ((port (or port (get-port))))
    ;; Load timezone database for local-time
    (local-time:reread-timezone-repository)
    (log:info "Timezone repository loaded")

    ;; Ensure default admin user exists
    (ensure-default-admin!)

    ;; Build and start the application
    (let ((app (build-app)))
      (setf *handler* (clackup app
                               :port port
                               :address address
                               :server :hunchentoot
                               :use-thread t
                               :silent nil))
      (log:info "Web server started on http://~A:~A" address port)
      *handler*)))

(defun stop! ()
  "Stop the running web server."
  (when *handler*
    (stop *handler*)
    (setf *handler* nil)
    (log:info "Web server stopped")))
