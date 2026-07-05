;;;; tests/integration/sicp-canonical-solutions.lisp --- One DB-backed
;;;; integration test that asserts every canonical SICP solution under
;;;; docs/sicp/*.md grades as :PASS against its sibling exercise.
;;;;
;;;; This replaces the per-notebook tests/game/notebooks/sicp-*.lisp
;;;; suite (one file per chapter section) that existed before the
;;;; module-based notebook registry was retired in favour of DB-backed
;;;; notebooks under the SICP course. The single deftest below
;;;; iterates over every (exercise, solution) pair in every SICP
;;;; markdown fixture and runs the exercise cell with the canonical
;;;; solution body injected, asserting the cell result status is :PASS.

(defpackage #:recurya/tests/integration/sicp-canonical-solutions
  (:use #:cl #:rove)
  (:import-from #:recurya/tests/support/db #:with-test-db #:create-test-user)
  (:import-from #:recurya/db/courses
                #:create-course!
                #:get-course-by-slug
                #:course-id)
  (:import-from #:recurya/db/notebooks
                #:create-notebook!
                #:notebook-id
                #:notebook-slug)
  (:import-from #:recurya/db/course-notebooks
                #:add-notebook-to-course!
                #:list-course-notebooks
                #:course-notebook-notebook)
  (:import-from #:recurya/game/notebook-parser #:parse-notebook-body)
  (:import-from #:recurya/game/notebook
                #:notebook-cells
                #:cell-kind
                #:cell-body
                #:cell-description
                #:run-cell
                #:notebook-cell-result-status))

(in-package #:recurya/tests/integration/sicp-canonical-solutions)

;;; ---------------------------------------------------------------------------
;;; Slug ordering: chapter.section.subsection
;;; ---------------------------------------------------------------------------

(defun parse-sicp-slug-numbers (slug)
  "Return the (CHAPTER SECTION SUBSECTION) integer triple parsed from SLUG.
   SLUG is expected to look like \"sicp-1-2-3\"; returns NIL when SLUG does
   not match the expected pattern."
  (let ((parts (cl-ppcre:split "-" slug)))
    (when (and (= (length parts) 4)
               (string= (first parts) "sicp"))
      (let ((nums (mapcar (lambda (s)
                            (handler-case (parse-integer s)
                              (error () nil)))
                          (rest parts))))
        (when (every #'integerp nums)
          nums)))))

(defun sicp-slug< (a b)
  "Total order over SICP slugs by (chapter section subsection) numerically.
   Falls back to STRING< when either slug is not a SICP slug."
  (let ((na (parse-sicp-slug-numbers a))
        (nb (parse-sicp-slug-numbers b)))
    (cond
      ((and na nb)
       (loop for x in na for y in nb
             do (cond ((< x y) (return t))
                      ((> x y) (return nil)))
             finally (return nil)))
      (t (string< a b)))))

;;; ---------------------------------------------------------------------------
;;; Fixture loader
;;; ---------------------------------------------------------------------------

(defun %sicp-markdown-files (&optional (dir #P"docs/sicp/"))
  "Return docs/sicp/*.md pathnames sorted by chapter.section.subsection."
  (let ((files (directory (merge-pathnames "*.md" dir))))
    (sort files #'sicp-slug< :key #'pathname-name)))

(defun %read-file-string (path)
  "Read PATH into a string."
  (with-open-file (s path :direction :input :external-format :utf-8)
    (with-output-to-string (out)
      (loop for line = (read-line s nil nil)
            while line do (write-line line out)))))

(defun load-sicp-fixtures! ()
  "Walk docs/sicp/*.md, parse each into cells, and persist them as
notebook + course_notebook rows under a freshly created \"sicp\"
course. Intended for use inside (with-test-db ...). Title is derived
from the slug as a fallback (the legacy registry that mapped slugs to
human-readable titles has been retired)."
  (let* ((author (create-test-user :email-prefix "sicp-fixtures"))
         (course (create-course! :title "SICP"
                                 :slug "sicp"
                                 :summary "SICP fixtures (test)"
                                 :status "published"
                                 :published-at (local-time:now)
                                 :author author))
         (course-uuid (course-id course)))
    (loop for path in (%sicp-markdown-files)
          for slug = (pathname-name path)
          for body-md = (%read-file-string path)
          for position from 0
          do (multiple-value-bind (cells parse-errors)
                 (parse-notebook-body body-md)
               (when parse-errors
                 (error "load-sicp-fixtures!: parse errors in ~A: ~S"
                        slug parse-errors))
               (let* ((cells-jsonb
                       (mapcar #'recurya/web/routes::cell->jsonb-form cells))
                      (nb (create-notebook!
                           :title (format nil "SICP ~A" slug)
                           :slug slug
                           :body-md body-md
                           :cells cells-jsonb
                           :author author
                           :status "published"
                           :published-at (local-time:now))))
                 (add-notebook-to-course! course-uuid
                                          (notebook-id nb)
                                          :position position))))
    course))

;;; ---------------------------------------------------------------------------
;;; Exercise runner
;;; ---------------------------------------------------------------------------

(defun run-exercise-with-solution (notebook ex-cell solution-body)
  "Run the EX-CELL exercise inside NOTEBOOK with SOLUTION-BODY substituted
in place of the exercise body. Returns the NOTEBOOK-CELL-RESULT struct
produced by RUN-CELL.

The codes vector is built up to and including the exercise cell index:
  - :code-eval cells contribute their original body so prior helper
    definitions are available to the solution.
  - the target exercise cell receives SOLUTION-BODY.
  - every other cell kind (prose, prior exercises, prior solutions)
    contributes the empty string."
  (let* ((cells (notebook-cells notebook))
         (ex-idx (position ex-cell cells :test #'eq))
         (codes (loop for c in cells
                      for i from 0
                      collect (cond ((= i ex-idx) solution-body)
                                    ((eq (cell-kind c) :code-eval)
                                     (cell-body c))
                                    (t "")))))
    (run-cell notebook ex-idx codes)))

;;; ---------------------------------------------------------------------------
;;; The single integration test
;;; ---------------------------------------------------------------------------

(deftest sicp-all-canonical-solutions-pass
  (testing "every (exercise, solution) pair across docs/sicp/*.md grades :pass"
    (with-test-db
      (load-sicp-fixtures!)
      (let* ((course (get-course-by-slug "sicp"))
             (cns (list-course-notebooks (course-id course)))
             (total-exercises 0)
             (passed 0))
        (dolist (cn cns)
          (let* ((nb-row (course-notebook-notebook cn))
                 (slug (notebook-slug nb-row))
                 (notebook (recurya/web/routes::notebook-row->notebook-struct
                            nb-row))
                 (cells (notebook-cells notebook))
                 (exercises (remove-if-not (lambda (c)
                                             (eq (cell-kind c) :code-exercise))
                                           cells))
                 (solutions (remove-if-not (lambda (c)
                                             (eq (cell-kind c) :code-solution))
                                           cells)))
            (dolist (ex exercises)
              (let ((sol (find (cell-description ex) solutions
                               :key #'cell-description :test #'string=)))
                (when sol
                  (incf total-exercises)
                  (let* ((result (run-exercise-with-solution
                                  notebook ex (cell-body sol)))
                         (status (notebook-cell-result-status result)))
                    (when (eq status :pass) (incf passed))
                    (ok (eq :pass status)
                        (format nil "~A / ~A"
                                slug
                                (cell-description ex)))))))))
        (format t "~&[sicp-canonical] ~A/~A exercises passed~%"
                passed total-exercises)
        (ok (plusp total-exercises) "expected to find at least one exercise")))))
