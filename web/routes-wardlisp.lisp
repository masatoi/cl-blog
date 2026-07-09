;;;; web/routes-wardlisp.lisp --- WardLisp puzzle and arena routes.

(defpackage #:recurya/web/routes-wardlisp
  (:use #:cl)
  (:import-from #:recurya/game/puzzle #:run-puzzle)
  (:import-from #:recurya/game/puzzles/registry #:get-puzzle #:all-puzzles)
  (:import-from #:recurya/web/ui/wardlisp-home)
  (:import-from #:recurya/web/ui/puzzle)
  (:import-from #:recurya/game/arena #:simulate-arena)
  (:import-from #:recurya/game/scenario #:default-scenario)
  (:import-from #:recurya/web/ui/arena)
  (:import-from #:recurya/web/ui/reference)
  (:import-from #:recurya/web/ui/playground)
  (:import-from #:wardlisp #:evaluate #:print-value)
  (:import-from #:recurya/web/i18n/core
                #:tr)
  (:import-from #:recurya/web/routes
                #:sicp-learn-redirect-handler
                #:sicp-notebook-redirect-handler
                #:sicp-cell-run-redirect-handler
                #:learn-sync-redirect-handler)
  (:export #:setup-wardlisp-routes))

(in-package #:recurya/web/routes-wardlisp)

;;; --- Response Helpers (same pattern as web/routes.lisp) ---

(defun html-response (body &key (status 200))
  "Create an HTML response."
  (list status '(:content-type "text/html; charset=utf-8") (list body)))

(defun get-param (params key)
  "Get a parameter value from the alist."
  (cdr (assoc key params :test #'string-equal)))

(defun get-path-param (params key)
  "Get a path parameter (keyword) from the alist."
  (cdr (assoc key params)))

;;; --- Handlers ---

(defun wardlisp-home-handler (params)
  "GET /wardlisp/ - Puzzle listing page."
  (declare (ignore params))
  (html-response
   (recurya/web/ui/wardlisp-home:render (all-puzzles))))

(defun puzzle-page-handler (params)
  "GET /wardlisp/puzzle/:id - Puzzle page with editor."
  (let* ((id-str (get-path-param params :id))
         (id (intern (string-upcase id-str) :keyword))
         (puzzle (get-puzzle id)))
    (if puzzle
        (html-response (recurya/web/ui/puzzle:render puzzle))
        (html-response (tr :wardlisp.puzzle.not_found_page) :status 404))))

(defun puzzle-run-handler (params)
  "POST /wardlisp/puzzle/:id/run - Execute and grade user code (HTMX fragment)."
  (let* ((id-str (get-path-param params :id))
         (id (intern (string-upcase id-str) :keyword))
         (code (get-param params "code"))
         (puzzle (get-puzzle id)))
    (if puzzle
        (let ((puzzle-result (run-puzzle puzzle (or code ""))))
          ;; Evaluate user code standalone to show its output
          (multiple-value-bind (eval-result eval-metrics)
              (handler-case
                  (evaluate (or code "")
                            :fuel 100000 :max-depth 200
                            :max-cons 10000 :max-output 10000
                            :max-integer 100000000000 :timeout 5)
                (error (e)
                  (values nil (list :error-message (format nil "~A" e)))))
            (let ((eval-error (getf eval-metrics :error-message))
                  (eval-output (print-value eval-result))
                  (print-output (getf eval-metrics :output)))
              (html-response
               (recurya/web/ui/puzzle:render-result
                puzzle-result
                :eval-output eval-output
                :eval-error eval-error
                :print-output print-output)))))
        (html-response (tr :wardlisp.puzzle.not_found_fragment)
                       :status 404))))

(defun arena-page-handler (params)
  "GET /wardlisp/arena - Arena page with code editor."
  (declare (ignore params))
  (html-response (recurya/web/ui/arena:render)))

(defun arena-run-handler (params)
  "POST /wardlisp/arena/run - Execute arena simulation (HTMX fragment)."
  (let* ((code (get-param params "code"))
         (result (simulate-arena (or code "") (default-scenario))))
    (html-response (recurya/web/ui/arena:render-result result))))

(defun reference-page-handler (params)
  "GET /wardlisp/reference - Language reference page."
  (declare (ignore params))
  (html-response (recurya/web/ui/reference:render)))

;;; --- Dynamic dispatch ---

(defun playground-handler (params)
  "GET /wardlisp/playground - Free-form code evaluation page."
  (declare (ignore params))
  (html-response (recurya/web/ui/playground:render)))

(defun playground-run-handler (params)
  "POST /wardlisp/playground/run - Evaluate user code (HTMX fragment)."
  (let ((code (get-param params "code")))
    (html-response (recurya/web/ui/playground:render-result (or code "")))))

(defun make-dynamic-handler (handler-symbol)
  "Create a handler that looks up the function by symbol at call time."
  (lambda (params)
    (funcall (symbol-function handler-symbol) params)))

;;; --- Route Setup ---

(defun setup-wardlisp-routes (app)
  "Register all WardLisp routes on the Ningle app.
   The /wardlisp/learn/* routes are now permanent redirects to the public
   handle-scoped notebook (/@<sicp-author>/<slug>) and course
   (/c/@<sicp-author>/sicp) endpoints — see recurya/web/routes for the
   redirect handlers."
  (setf (ningle/app:route app "/wardlisp/")
        (make-dynamic-handler 'wardlisp-home-handler))
  (setf (ningle/app:route app "/wardlisp/puzzle/:id")
        (make-dynamic-handler 'puzzle-page-handler))
  (setf (ningle/app:route app "/wardlisp/puzzle/:id/run" :method :post)
        (make-dynamic-handler 'puzzle-run-handler))
  (setf (ningle/app:route app "/wardlisp/arena")
        (make-dynamic-handler 'arena-page-handler))
  (setf (ningle/app:route app "/wardlisp/arena/run" :method :post)
        (make-dynamic-handler 'arena-run-handler))
  (setf (ningle/app:route app "/wardlisp/reference")
        (make-dynamic-handler 'reference-page-handler))
  (setf (ningle/app:route app "/wardlisp/learn")
        (make-dynamic-handler 'sicp-learn-redirect-handler))
  (setf (ningle/app:route app "/wardlisp/learn/:id")
        (make-dynamic-handler 'sicp-notebook-redirect-handler))
  (setf (ningle/app:route app "/wardlisp/learn/:id/cells/:index/run" :method :post)
        (make-dynamic-handler 'sicp-cell-run-redirect-handler))
  (setf (ningle/app:route app "/wardlisp/learn/sync" :method :post)
        (make-dynamic-handler 'learn-sync-redirect-handler))
  (setf (ningle/app:route app "/wardlisp/playground")
        (make-dynamic-handler 'playground-handler))
  (setf (ningle/app:route app "/wardlisp/playground/run" :method :post)
        (make-dynamic-handler 'playground-run-handler))
  app)
