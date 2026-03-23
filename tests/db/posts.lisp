;;;; tests/db/posts.lisp --- Tests for post CRUD operations (db/posts).

(defpackage #:cl-blog/tests/db/posts
  (:use #:cl
        #:rove)
  (:import-from #:cl-blog/tests/support/db
                #:with-test-db
                #:create-test-post)
  (:import-from #:cl-blog/db/posts
                #:post-id
                #:post-title
                #:post-slug
                #:post-body
                #:post-excerpt
                #:post-status
                #:post-published-at
                #:create-post!
                #:get-post-by-id
                #:get-post-by-slug
                #:update-post!
                #:delete-post!
                #:list-posts
                #:count-posts
                #:slugify))

(in-package #:cl-blog/tests/db/posts)

(deftest slugify-test
  (testing "slugify converts titles to URL-friendly slugs"
    (ok (equal "hello-world" (slugify "Hello World")))
    (ok (equal "my-first-post" (slugify "My First Post!")))
    (ok (equal "foo-bar-baz" (slugify "  foo--bar--baz  ")))
    (ok (equal "already-a-slug" (slugify "already-a-slug")))
    (ok (equal "numbers-123-ok" (slugify "Numbers 123 OK")))))

(deftest create-and-fetch-post
  (testing "create-post! persists and get-post-by-id retrieves"
    (with-test-db
      (let* ((created (create-post! :title "Test Post"
                                    :body "Hello, this is a test."))
             (fetched (get-post-by-id (post-id created))))
        (ok (post-id created))
        (ok (equal (post-id created) (post-id fetched)))
        (ok (equal "Test Post" (post-title fetched)))
        (ok (equal "test-post" (post-slug fetched)))
        (ok (equal "Hello, this is a test." (post-body fetched)))
        (ok (equal "draft" (post-status fetched)))))))

(deftest fetch-post-by-slug
  (testing "get-post-by-slug finds by unique slug"
    (with-test-db
      (let ((created (create-post! :title "Slug Lookup Test"
                                   :body "Body content.")))
        (let ((fetched (get-post-by-slug "slug-lookup-test")))
          (ok fetched)
          (ok (equal (post-id created) (post-id fetched))))
        (ok (null (get-post-by-slug "nonexistent-slug")))))))

(deftest update-post-test
  (testing "update-post! modifies mutable fields"
    (with-test-db
      (let* ((created (create-post! :title "Before"
                                    :body "Original body."))
             (updated (update-post! (post-id created)
                                    :title "After"
                                    :body "Updated body."
                                    :status "published"
                                    :excerpt "A short summary.")))
        (ok (equal "After" (post-title updated)))
        (ok (equal "Updated body." (post-body updated)))
        (ok (equal "published" (post-status updated)))
        (ok (equal "A short summary." (post-excerpt updated)))))))

(deftest delete-post-test
  (testing "delete-post! removes row"
    (with-test-db
      (let ((p (create-post! :title "Delete Me"
                             :body "Will be deleted.")))
        (ok (eq t (delete-post! (post-id p))))
        (ok (null (get-post-by-id (post-id p))))
        (ok (null (delete-post! (post-id p))))))))

(deftest list-and-count-posts-test
  (testing "list-posts and count-posts with status filter"
    (with-test-db
      (create-post! :title "Draft One" :body "D1" :status "draft")
      (create-post! :title "Draft Two" :body "D2" :status "draft")
      (create-post! :title "Published One" :body "P1" :status "published")
      (ok (= 3 (count-posts)))
      (ok (= 2 (count-posts :status "draft")))
      (ok (= 1 (count-posts :status "published")))
      (ok (= 3 (length (list-posts))))
      (ok (= 2 (length (list-posts :status "draft"))))
      (ok (= 1 (length (list-posts :status "published")))))))
