;;;; web/ui/blog.lisp --- Public blog listing page (no auth required).

(defpackage #:recurya/web/ui/blog
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:recurya/web/ui/layout
                #:page-shell
                #:common-styles
                #:format-timestamp)
  (:export #:render))

(in-package #:recurya/web/ui/blog)

(defparameter *blog-styles*
  "/* Public blog listing styles */
body {
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  margin: 0;
  background: #f8fafc;
  color: #0f172a;
  line-height: 1.6;
}

main {
  max-width: 760px;
  margin: 0 auto;
  padding: 3rem 1.5rem 4rem;
}

.blog-header {
  text-align: center;
  margin-bottom: 3rem;
}

.blog-header h1 {
  font-size: 2.2rem;
  letter-spacing: -0.03em;
  margin-bottom: 0.5rem;
}

.blog-header p {
  color: #64748b;
  font-size: 1.05rem;
}

.post-card {
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08);
  padding: 1.75rem 2rem;
  margin-bottom: 1.5rem;
  transition: box-shadow 0.15s ease;
}

.post-card:hover {
  box-shadow: 0 4px 12px rgba(0,0,0,0.12);
}

.post-card__title {
  margin: 0 0 0.5rem;
  font-size: 1.35rem;
  letter-spacing: -0.02em;
}

.post-card__title a {
  color: #0f172a;
  text-decoration: none;
}

.post-card__title a:hover {
  color: #0ea5e9;
}

.post-card__meta {
  color: #64748b;
  font-size: 0.85rem;
  margin-bottom: 0.75rem;
}

.post-card__excerpt {
  color: #475569;
  line-height: 1.65;
  margin-bottom: 1rem;
}

.post-card__read-more {
  color: #0ea5e9;
  font-weight: 600;
  text-decoration: none;
  font-size: 0.9rem;
}

.post-card__read-more:hover {
  text-decoration: underline;
}

.pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  margin-top: 2rem;
  padding-top: 1.5rem;
  border-top: 1px solid #e2e8f0;
}

.pagination-info {
  color: #64748b;
  font-size: 0.9rem;
}

.pagination-nav {
  display: flex;
  gap: 0.5rem;
}

.pagination-btn {
  display: inline-flex;
  padding: 0.5rem 1rem;
  border: 1px solid #cbd5e1;
  border-radius: 8px;
  background: #fff;
  color: #0f172a;
  font-weight: 500;
  font-size: 0.9rem;
  text-decoration: none;
}

.pagination-btn:hover {
  background: #f1f5f9;
  text-decoration: none;
}

.pagination-btn.disabled {
  opacity: 0.5;
  cursor: not-allowed;
  pointer-events: none;
}

.empty-blog {
  text-align: center;
  color: #64748b;
  padding: 3rem 0;
}")

(defun render (&key posts pagination)
  "Render the public blog listing page as an HTML string."
  (let ((posts (or posts 'nil)))
    (spinneret:with-html-string
      (:doctype)
      (:html
       (:head (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title "Blog")
        (:style (:raw *blog-styles*)))
       (:body
        (:main
         (:div :class "blog-header"
          (:h1 "Blog")
          (:p "Thoughts, tutorials, and updates."))
         (if posts
             (progn
              (dolist (post posts)
                (let ((slug (getf post :slug))
                      (title (getf post :title))
                      (excerpt (getf post :excerpt))
                      (published-at (getf post :published-at))
                      (author-name (getf post :author-name)))
                  (:div :class "post-card"
                   (:h2 :class "post-card__title"
                    (:a :href (format nil "/blog/~A" slug) title))
                   (:div :class "post-card__meta"
                    (format nil "~@[~A~]~@[ · ~A~]"
                            author-name
                            (format-timestamp published-at)))
                   (when (and excerpt (string/= excerpt ""))
                     (:p :class "post-card__excerpt" excerpt))
                   (:a :class "post-card__read-more"
                    :href (format nil "/blog/~A" slug) "Read more →"))))
              ;; Pagination
              (when pagination
                (let ((current-page (getf pagination :current-page))
                      (total-pages (getf pagination :total-pages))
                      (has-prev (getf pagination :has-prev))
                      (has-next (getf pagination :has-next))
                      (prev-url (getf pagination :prev-url))
                      (next-url (getf pagination :next-url)))
                  (:div :class "pagination"
                   (:span :class "pagination-info"
                    (format nil "Page ~A of ~A" current-page total-pages))
                   (:nav :class "pagination-nav"
                    (if has-prev
                        (:a :class "pagination-btn" :href prev-url "← Previous")
                        (:span :class "pagination-btn disabled" "← Previous"))
                    (if has-next
                        (:a :class "pagination-btn" :href next-url "Next →")
                        (:span :class "pagination-btn disabled" "Next →")))))))
             (:p :class "empty-blog" "No posts yet. Check back soon!"))))))))
