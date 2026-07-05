;;;; db/novel.lisp --- CRUD for per-reader novel state.
(defpackage #:recurya/db/novel
  (:use #:cl)
  (:import-from #:mito #:find-dao #:insert-dao #:save-dao)
  (:import-from #:recurya/db/core #:ensure-uuid)
  (:import-from #:recurya/utils/common #:parse-json #:json->string)
  (:import-from #:recurya/models/novel-state
                #:novel-state-flags #:novel-state-scene-index)
  (:export #:get-novel-state #:upsert-novel-state
           #:novel-state-flags-alist))

(in-package #:recurya/db/novel)

(defun %alist->ht (alist)
  "Convert an alist (flag-keyword -> value) to a string-keyed hash-table."
  (let ((h (make-hash-table :test 'equal)))
    (dolist (pair alist h)
      (setf (gethash (string-downcase (symbol-name (car pair))) h) (cdr pair)))))

(defun get-novel-state (user-id notebook-id)
  "Return the NOVEL-STATE row for (USER-ID, NOTEBOOK-ID), or NIL."
  (find-dao 'novel-state :user-id (ensure-uuid user-id) :notebook-id notebook-id))

(defun upsert-novel-state (user-id notebook-id &key flags scene-index)
  "Insert or update the per-reader novel state. FLAGS is an alist
   (flag-keyword -> value) serialized to JSON. Returns the row."
  (let* ((uid (ensure-uuid user-id))
         (flags-json (json->string (%alist->ht flags)))
         (existing (find-dao 'novel-state :user-id uid :notebook-id notebook-id)))
    (if existing
        (progn
          (when flags (setf (novel-state-flags existing) flags-json))
          (when scene-index (setf (novel-state-scene-index existing) scene-index))
          (save-dao existing))
        (insert-dao (make-instance 'novel-state
                                   :user-id uid :notebook-id notebook-id
                                   :flags flags-json
                                   :scene-index (or scene-index 0))))))

(defun novel-state-flags-alist (row)
  "Parse ROW's flags JSON back to an alist (flag-keyword -> value)."
  (let ((ht (parse-json (novel-state-flags row))))
    (when (hash-table-p ht)
      (loop for k being the hash-keys of ht using (hash-value v)
            collect (cons (intern (string-upcase k) :keyword) v)))))
