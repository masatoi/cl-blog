;;;; tests/db/notebooks.lisp --- Tests for notebook CRUD operations.

(defpackage #:recurya/tests/db/notebooks
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db
                #:create-test-user)
  (:import-from #:recurya/db/notebooks
                #:notebook-id
                #:notebook-slug
                #:notebook-title
                #:notebook-body-md
                #:notebook-status
                #:notebook-visibility
                #:notebook-author-id
                #:create-notebook!
                #:get-notebook-by-id
                #:get-notebook-by-slug
                #:update-notebook!
                #:delete-notebook!
                #:list-notebooks
                #:count-notebooks
                #:notebook-cells-parsed)
  (:import-from #:recurya/db/users
                #:users-id))

(in-package #:recurya/tests/db/notebooks)

(deftest create-and-get-by-id
  (testing "create-notebook! persists and get-notebook-by-id retrieves"
    (with-test-db
      (let* ((u (create-test-user))
             (nb (create-notebook!
                  :title "T1"
                  :body-md "===prose===
x"
                  :cells '()
                  :author u))
             (id (notebook-id nb)))
        (let ((found (get-notebook-by-id id)))
          (ok found)
          (ok (string= "T1" (notebook-title found)))
          (ok (string= "t1" (notebook-slug found)))
          (ok (string= "draft" (notebook-status found)))
          (ok (equal (users-id u) (notebook-author-id found))))))))

(deftest fetch-by-slug
  (testing "get-notebook-by-slug finds by unique slug"
    (with-test-db
      (let* ((u (create-test-user))
             (nb (create-notebook!
                  :title "Slug Lookup"
                  :body-md "===prose===
y"
                  :cells '()
                  :author u)))
        (let ((found (get-notebook-by-slug "slug-lookup")))
          (ok found)
          (ok (equal (notebook-id nb) (notebook-id found))))
        (ok (null (get-notebook-by-slug "no-such-notebook")))))))

(deftest get-by-id-missing-returns-nil
  (with-test-db
    (ok (null (get-notebook-by-id "00000000-0000-0000-0000-000000000000")))))

(deftest update-notebook-test
  (testing "update-notebook! modifies provided fields and returns instance"
    (with-test-db
      (let* ((u (create-test-user))
             (nb (create-notebook!
                  :title "Before"
                  :body-md "===prose===
old"
                  :cells '()
                  :author u))
             (updated (update-notebook!
                       (notebook-id nb)
                       :title "After"
                       :body-md "===prose===
new"
                       :status "published")))
        (ok updated)
        (ok (string= "After" (notebook-title updated)))
        (ok (string= "published" (notebook-status updated)))
        (ok (search "new" (notebook-body-md updated))))))
  (testing "update on missing id returns NIL"
    (with-test-db
      (ok (null (update-notebook!
                 "00000000-0000-0000-0000-000000000000"
                 :title "X"))))))

(deftest delete-notebook-test
  (testing "delete-notebook! removes row and returns T"
    (with-test-db
      (let* ((u (create-test-user))
             (nb (create-notebook!
                  :title "To Delete"
                  :body-md "===prose===
bye"
                  :cells '()
                  :author u))
             (id (notebook-id nb)))
        (ok (eq t (delete-notebook! id)))
        (ok (null (get-notebook-by-id id))))))
  (testing "delete on missing id returns NIL"
    (with-test-db
      (ok (null (delete-notebook!
                 "00000000-0000-0000-0000-000000000000"))))))

(deftest list-notebooks-test
  (testing "list-notebooks returns newest first; status and author filters work"
    (with-test-db
      (let ((u1 (create-test-user :email-prefix "alice"))
             (u2 (create-test-user :email-prefix "bob")))
        (create-notebook! :title "A1" :body-md "===prose===
a1" :cells '() :author u1 :status "published")
        (create-notebook! :title "A2" :body-md "===prose===
a2" :cells '() :author u1 :status "draft")
        (create-notebook! :title "B1" :body-md "===prose===
b1" :cells '() :author u2 :status "published")
        (let ((all (list-notebooks)))
          (ok (= 3 (length all))))
        (let ((pubs (list-notebooks :status "published")))
          (ok (= 2 (length pubs)))
          (ok (every (lambda (nb) (string= "published" (notebook-status nb)))
                     pubs)))
        (let ((u1-nbs (list-notebooks :author-id (users-id u1))))
          (ok (= 2 (length u1-nbs)))
          (ok (every (lambda (nb) (equal (users-id u1) (notebook-author-id nb)))
                     u1-nbs))))))
  (testing "limit and offset paginate"
    (with-test-db
      (let ((u (create-test-user)))
        (dotimes (i 5)
          (create-notebook!
           :title (format nil "T~A" i)
           :slug (format nil "t~A" i)
           :body-md "===prose===
x"
           :cells '()
           :author u))
        (let ((page1 (list-notebooks :limit 2)))
          (ok (= 2 (length page1))))
        (let ((page2 (list-notebooks :limit 2 :offset 2)))
          (ok (= 2 (length page2))))
        (let ((page3 (list-notebooks :limit 2 :offset 4)))
          (ok (= 1 (length page3))))))))

(deftest count-notebooks-test
  (testing "count-notebooks returns total and filters by status / author"
    (with-test-db
      (let ((u1 (create-test-user :email-prefix "carol"))
             (u2 (create-test-user :email-prefix "dave")))
        (create-notebook! :title "C1" :body-md "===prose===
c1" :cells '() :author u1 :status "published")
        (create-notebook! :title "C2" :body-md "===prose===
c2" :cells '() :author u1 :status "draft")
        (create-notebook! :title "D1" :body-md "===prose===
d1" :cells '() :author u2 :status "published")
        (ok (= 3 (count-notebooks)))
        (ok (= 2 (count-notebooks :status "published")))
        (ok (= 1 (count-notebooks :status "draft")))
        (ok (= 2 (count-notebooks :author-id (users-id u1))))))))

(deftest list-notebooks-filters-visibility
  (testing "list-notebooks filters by :visibility"
    (with-test-db
      (let ((u (create-test-user)))
        (create-notebook! :title "P" :body-md "===prose===
p" :cells '() :author u
                          :status "published" :visibility "public")
        (create-notebook! :title "Q" :body-md "===prose===
q" :cells '() :author u
                          :status "published" :visibility "private")
        (let ((pub (list-notebooks :status "published" :visibility "public"))
              (pri (list-notebooks :status "published" :visibility "private")))
          (ok (= 1 (length pub)))
          (ok (every (lambda (nb)
                       (string= "public" (notebook-visibility nb)))
                     pub))
          (ok (= 1 (length pri)))
          (ok (every (lambda (nb)
                       (string= "private" (notebook-visibility nb)))
                     pri)))))))

(deftest count-notebooks-filters-visibility
  (testing "count-notebooks filters by :visibility"
    (with-test-db
      (let ((u (create-test-user)))
        (create-notebook! :title "P" :body-md "===prose===
p" :cells '() :author u
                          :status "published" :visibility "public")
        (create-notebook! :title "Q" :body-md "===prose===
q" :cells '() :author u
                          :status "published" :visibility "private")
        (create-notebook! :title "R" :body-md "===prose===
r" :cells '() :author u
                          :status "draft" :visibility "private")
        (ok (= 1 (count-notebooks :visibility "public")))
        (ok (= 2 (count-notebooks :visibility "private")))
        (ok (= 1 (count-notebooks :status "published" :visibility "public")))
        (ok (= 1 (count-notebooks :status "published" :visibility "private")))))))

(deftest cells-jsonb-roundtrip
  (testing "cells written as a list come back parseable as a 2-element collection"
    (with-test-db
      (let* ((cells '((:cell-id "abc" :kind "prose"     :body-md "x")
                      (:cell-id "def" :kind "code-eval" :body    "(+ 1 2)")))
             (u  (create-test-user))
             (nb (create-notebook!
                  :title "x"
                  :body-md "==="
                  :cells cells
                  :author u))
             (out (notebook-cells-parsed
                   (get-notebook-by-id (notebook-id nb)))))
        (ok (= (length cells) (length out)))))))

(deftest notebook-per-author-slug
  (testing "different authors can share the same slug"
    (with-test-db
      (let ((u1 (create-test-user :email-prefix "alice" :handle "alice"))
             (u2 (create-test-user :email-prefix "bob" :handle "bob")))
        (create-notebook! :slug "intro"
                          :title "Alice intro"
                          :body-md "===prose===
a"
                          :cells '()
                          :author u1)
        (ok (create-notebook! :slug "intro"
                              :title "Bob intro"
                              :body-md "===prose===
b"
                              :cells '()
                              :author u2)))))
  (testing "same author cannot reuse slug"
    (with-test-db
      (let ((u (create-test-user :email-prefix "carol" :handle "carol")))
        (create-notebook! :slug "x"
                          :title "X"
                          :body-md "===prose===
x"
                          :cells '()
                          :author u)
        (ok (signals
              (create-notebook! :slug "x"
                                :title "Y"
                                :body-md "===prose===
y"
                                :cells '()
                                :author u)
              'error))))))
