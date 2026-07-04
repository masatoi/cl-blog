;;;; game/notebook-jsonb.lisp --- Cell <-> JSONB hash-table conversion.
;;;;
;;;; Pure conversion between notebook cell structs and the hash-table
;;;; shape stored in the notebook.cells JSONB column. Lives at the game
;;;; layer (no web dependency) so both web/routes and the official-content
;;;; seeder can share it.

(defpackage #:recurya/game/notebook-jsonb
  (:use #:cl)
  (:import-from #:recurya/game/notebook
                #:cell-id
                #:cell-kind
                #:cell-body
                #:cell-description
                #:cell-test-cases
                #:cell-gated-p
                #:make-cell)
  (:import-from #:recurya/game/puzzle
                #:make-test-case
                #:test-case-input
                #:test-case-expected
                #:test-case-description)
  (:export #:cell->jsonb-form
           #:jsonb-hash->cell))

(in-package #:recurya/game/notebook-jsonb)

(defun cell->jsonb-form (cell)
  "Convert a cell struct into a hash-table that jzon serializes as a JSON
object. Pairs with `jsonb-hash->cell' to round-trip cells through the
JSONB column while preserving stable cell ids across edits."
  (let ((h (make-hash-table :test 'equal)))
    (setf (gethash "cell-id"     h) (or (cell-id cell) "")
          (gethash "kind"        h) (string-downcase (symbol-name (cell-kind cell)))
          (gethash "body"        h) (or (cell-body cell) "")
          (gethash "description" h) (cell-description cell)
          (gethash "gated"       h) (and (cell-gated-p cell) t)
          (gethash "test-cases"  h)
          (mapcar (lambda (tc)
                    (let ((th (make-hash-table :test 'equal)))
                      (setf (gethash "input"       th) (test-case-input tc)
                            (gethash "expected"    th) (test-case-expected tc)
                            (gethash "description" th) (test-case-description tc))
                      th))
                  (cell-test-cases cell)))
    h))

(defun jsonb-hash->cell (h)
  "Reconstruct a cell struct from a JSONB hash-table produced by
`cell->jsonb-form'. Used to seed parse-notebook-body's existing-cells
so cell ids stay stable across edits."
  (let ((kind-str (gethash "kind" h ""))
        (raw-tcs  (gethash "test-cases" h #())))
    (make-cell
     :id (or (gethash "cell-id" h) "")
     :kind (if (and kind-str (plusp (length kind-str)))
               (intern (string-upcase kind-str) :keyword)
               :prose)
     :body (or (gethash "body" h) "")
     :description (or (gethash "description" h) "")
     :gated-p (let ((g (gethash "gated" h)))
                (cond ((null g) nil)
                      ((eq g t) t)
                      ((equal g "false") nil)
                      ((eq g :false) nil)
                      (t (and g t))))
     :test-cases (mapcar
                  (lambda (th)
                    (make-test-case
                     :input       (or (gethash "input" th) "")
                     :expected    (or (gethash "expected" th) "")
                     :description (or (gethash "description" th) "")))
                  (coerce raw-tcs 'list)))))
