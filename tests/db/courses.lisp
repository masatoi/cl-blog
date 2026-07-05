;;;; tests/db/courses.lisp --- Tests for course CRUD operations.

(defpackage #:recurya/tests/db/courses
  (:use #:cl
        #:rove)
  (:import-from #:recurya/tests/support/db
                #:with-test-db
                #:create-test-user)
  (:import-from #:recurya/db/courses
                #:course-id
                #:course-slug
                #:course-title
                #:course-status
                #:course-visibility
                #:course-published-at
                #:course-author-id
                #:create-course!
                #:get-course-by-id
                #:get-course-by-slug
                #:update-course!
                #:delete-course!
                #:list-courses
                #:count-courses)
  (:import-from #:recurya/db/users
                #:users-id))

(in-package #:recurya/tests/db/courses)

(deftest create-and-get-course-by-id
  (testing "create-course! persists and get-course-by-id retrieves"
    (with-test-db
      (let* ((u (create-test-user))
             (c (create-course! :title "C1" :author u))
             (id (course-id c)))
        (let ((found (get-course-by-id id)))
          (ok found)
          (ok (string= "C1" (course-title found)))
          (ok (string= "c1" (course-slug found)))
          (ok (string= "draft" (course-status found)))
          (ok (equal (users-id u) (course-author-id found))))))))

(deftest fetch-course-by-slug
  (testing "get-course-by-slug finds by unique slug"
    (with-test-db
      (let* ((u (create-test-user))
             (c (create-course! :title "Course Lookup" :author u)))
        (let ((found (get-course-by-slug "course-lookup")))
          (ok found)
          (ok (equal (course-id c) (course-id found))))
        (ok (null (get-course-by-slug "no-such-course")))))))

(deftest get-course-by-id-missing-returns-nil
  (with-test-db
    (ok (null (get-course-by-id "00000000-0000-0000-0000-000000000000")))))

(deftest update-course-test
  (testing "update-course! modifies provided fields and returns instance"
    (with-test-db
      (let* ((u (create-test-user))
             (c (create-course! :title "Before" :author u))
             (ts (local-time:now))
             (updated
              (update-course! (course-id c)
                              :title "After"
                              :status "published"
                              :published-at ts)))
        (ok updated)
        (ok (string= "After" (course-title updated)))
        (ok (string= "published" (course-status updated)))
        (ok (course-published-at updated))))))

(deftest update-course-missing-returns-nil
  (testing "update on missing id returns NIL"
    (with-test-db
      (ok
       (null
        (update-course! "00000000-0000-0000-0000-000000000000"
                        :title "X"))))))

(deftest delete-course-test
  (testing "delete-course! removes row and returns T"
    (with-test-db
      (let* ((u (create-test-user))
             (c (create-course! :title "To Delete" :author u))
             (id (course-id c)))
        (ok (eq t (delete-course! id)))
        (ok (null (get-course-by-id id)))))))

(deftest delete-course-missing-returns-nil
  (testing "delete on missing id returns NIL"
    (with-test-db
      (ok
       (null
        (delete-course! "00000000-0000-0000-0000-000000000000"))))))

(deftest list-courses-test
  (testing "list-courses returns newest first; status and author filters work"
    (with-test-db
      (let ((u1 (create-test-user :email-prefix "alice"))
            (u2 (create-test-user :email-prefix "bob")))
        (create-course! :title "A1" :author u1 :status "published")
        (create-course! :title "A2" :author u1 :status "draft")
        (create-course! :title "B1" :author u2 :status "published")
        (let ((all (list-courses)))
          (ok (= 3 (length all))))
        (let ((pubs (list-courses :status "published")))
          (ok (= 2 (length pubs)))
          (ok (every (lambda (c) (string= "published" (course-status c)))
                     pubs)))
        (let ((u1-cs (list-courses :author-id (users-id u1))))
          (ok (= 2 (length u1-cs)))
          (ok (every (lambda (c) (equal (users-id u1) (course-author-id c)))
                     u1-cs))))))
  (testing "limit and offset paginate"
    (with-test-db
      (let ((u (create-test-user)))
        (dotimes (i 5)
          (create-course! :title (format nil "T~A" i)
                          :slug (format nil "t~A" i)
                          :author u))
        (let ((page1 (list-courses :limit 2)))
          (ok (= 2 (length page1))))
        (let ((page2 (list-courses :limit 2 :offset 2)))
          (ok (= 2 (length page2))))
        (let ((page3 (list-courses :limit 2 :offset 4)))
          (ok (= 1 (length page3))))))))

(deftest count-courses-test
  (testing "count-courses returns total and filters by status / author"
    (with-test-db
      (let ((u1 (create-test-user :email-prefix "carol"))
            (u2 (create-test-user :email-prefix "dave")))
        (create-course! :title "C1" :author u1 :status "published")
        (create-course! :title "C2" :author u1 :status "draft")
        (create-course! :title "D1" :author u2 :status "published")
        (ok (= 3 (count-courses)))
        (ok (= 2 (count-courses :status "published")))
        (ok (= 1 (count-courses :status "draft")))
        (ok (= 2 (count-courses :author-id (users-id u1))))))))

(deftest list-courses-filters-visibility
  (testing "list-courses filters by :visibility"
    (with-test-db
      (let ((u (create-test-user)))
        (create-course! :title "P" :author u
                        :status "published" :visibility "public")
        (create-course! :title "Q" :author u
                        :status "published" :visibility "private")
        (let ((pub (list-courses :status "published" :visibility "public"))
              (pri (list-courses :status "published" :visibility "private")))
          (ok (= 1 (length pub)))
          (ok (every (lambda (c) (string= "public" (course-visibility c))) pub))
          (ok (= 1 (length pri)))
          (ok (every (lambda (c) (string= "private" (course-visibility c))) pri)))))))

(deftest count-courses-filters-visibility
  (testing "count-courses filters by :visibility"
    (with-test-db
      (let ((u (create-test-user)))
        (create-course! :title "P" :author u
                        :status "published" :visibility "public")
        (create-course! :title "Q" :author u
                        :status "published" :visibility "private")
        (create-course! :title "R" :author u
                        :status "draft" :visibility "private")
        (ok (= 1 (count-courses :visibility "public")))
        (ok (= 2 (count-courses :visibility "private")))
        (ok (= 1 (count-courses :status "published" :visibility "public")))
        (ok (= 1 (count-courses :status "published" :visibility "private")))))))

(deftest course-per-author-slug
  (testing "different authors can share the same slug"
    (with-test-db
      (let ((u1 (create-test-user :email-prefix "alice" :handle "alice"))
            (u2 (create-test-user :email-prefix "bob" :handle "bob")))
        (create-course! :slug "intro" :title "Alice intro" :author u1)
        (ok (create-course! :slug "intro" :title "Bob intro" :author u2)))))
  (testing "same author cannot reuse slug"
    (with-test-db
      (let ((u (create-test-user :email-prefix "carol" :handle "carol")))
        (create-course! :slug "x" :title "X" :author u)
        (ok (signals
              (create-course! :slug "x" :title "Y" :author u)
              'error))))))
