;;;; web/ui/blog-post.lisp --- Public single blog post view.

(defpackage #:cl-blog/web/ui/blog-post
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:import-from #:cl-blog/web/ui/layout
                #:format-timestamp)
  (:export #:render))

(in-package #:cl-blog/web/ui/blog-post)

(defparameter *blog-post-styles*
  "/* Public single blog post styles */
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

.back-link {
  display: inline-block;
  color: #0ea5e9;
  font-weight: 600;
  text-decoration: none;
  font-size: 0.9rem;
  margin-bottom: 2rem;
}

.back-link:hover {
  text-decoration: underline;
}

.post-article {
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08);
  padding: 2.5rem 2.5rem;
}

.post-article__title {
  font-size: 2rem;
  letter-spacing: -0.03em;
  margin: 0 0 0.75rem;
  line-height: 1.25;
}

.post-article__meta {
  color: #64748b;
  font-size: 0.9rem;
  margin-bottom: 2rem;
  padding-bottom: 1.5rem;
  border-bottom: 1px solid #e2e8f0;
}

.post-article__body {
  line-height: 1.75;
  color: #1e293b;
}

.post-article__body p {
  margin-bottom: 1.25rem;
}

.not-found {
  text-align: center;
  padding: 3rem 0;
}

.not-found h1 {
  color: #64748b;
}

.not-found a {
  color: #0ea5e9;
  font-weight: 600;
  text-decoration: none;
}

.not-found a:hover {
  text-decoration: underline;
}")

(defun render (&key post)
  "Render the public single blog post page as an HTML string.

POST is a plist with :title :slug :body :published-at :excerpt."
  (let ((title (getf post :title))
        (body (getf post :body))
        (published-at (getf post :published-at))
        (author-name (getf post :author-name)))
    (spinneret:with-html-string
      (:doctype)
      (:html
       (:head (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title (or title "Post Not Found"))
        (:style (:raw *blog-post-styles*)))
       (:body
        (:main
         (if post
             (progn
              (:a :class "back-link" :href "/blog" "← Back to blog")
              (:article :class "post-article"
               (:h1 :class "post-article__title" title)
               (:div :class "post-article__meta"
                (format nil "~@[~A~]~@[ · ~A~]"
                        author-name
                        (format-timestamp published-at)))
               (:div :class "post-article__body"
                (:raw body))))
             (progn
              (:div :class "not-found"
               (:h1 "Post not found")
               (:p (:a :href "/blog" "← Back to blog")))))))))))
