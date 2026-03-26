;;;; tests/all.lisp --- Aggregate test runner for all recurya test suites.

(defpackage #:recurya/tests/all
  (:use #:cl)
  (:export #:run-all-tests))

(in-package #:recurya/tests/all)

(defparameter *test-packages*
  '(:recurya/tests/utils/common
    :recurya/tests/db/core
    :recurya/tests/db/jsonb
    :recurya/tests/db/users
    :recurya/tests/db/posts
    :recurya/tests/web/auth
    :recurya/tests/web/routes
    ;; WardLisp integration tests
    :recurya/tests/wardlisp-integration
    ;; Game tests
    :recurya/tests/game/puzzle
    :recurya/tests/game/arena)
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
