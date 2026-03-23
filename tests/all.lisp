(defpackage #:cl-blog/tests/all
  (:use #:cl)
  (:export #:run-all-tests))

(in-package #:cl-blog/tests/all)

(defparameter *test-packages*
  '(:cl-blog/tests/utils/common
    :cl-blog/tests/db/core
    :cl-blog/tests/db/jsonb
    :cl-blog/tests/db/users
    :cl-blog/tests/db/posts
    :cl-blog/tests/web/auth
    :cl-blog/tests/web/routes)
  "List of all test packages to run.")

(defun run-all-tests ()
  "Run all test packages and return T if all pass, NIL otherwise."
  ;; Load clack-test for HTTP integration tests (system name differs from package name)
  (ql:quickload :clack-test :silent t)
  (let ((all-passed t))
    (dolist (pkg *test-packages*)
      (format t "~%=== Running tests for ~A ===~%" pkg)
      (handler-case
          (unless (rove:run pkg)
            (setf all-passed nil))
        (error (e)
          (format t "Error running ~A: ~A~%" pkg e)
          (setf all-passed nil))))
    all-passed))
