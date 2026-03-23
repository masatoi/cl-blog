(defsystem "cl-blog"
  :class :package-inferred-system
  :version "0.1.0"
  :author "Satoshi Imai"
  :license "MIT"
  :pathname "./"
  :depends-on ("mito"
               "local-time"
               "alexandria"
               "log4cl"
               "com.inuoe.jzon"
               "uuid"
               ;; Web framework
               "ningle"
               "clack"
               "clack-handler-hunchentoot"
               "lack"
               "spinneret"
               "ironclad"
               "babel"
               "hunchentoot"
               "cl-ppcre"
               ;; Shared utilities
               "cl-blog/utils/common"
               ;; Database layer
               "cl-blog/db/core"
               "cl-blog/db/jsonb"
               "cl-blog/db/users"
               "cl-blog/db/posts"
               "cl-blog/db"
               ;; Models
               "cl-blog/models/users"
               "cl-blog/models/post"
               ;; Web layer
               "cl-blog/web/app"
               "cl-blog/web/auth"
               "cl-blog/web/ui/styles"
               "cl-blog/web/ui/layout"
               "cl-blog/web/ui/login"
               "cl-blog/web/ui/signup"
               "cl-blog/web/ui/errors"
               "cl-blog/web/ui/account"
               ;; Blog UI
               "cl-blog/web/ui/posts"
               "cl-blog/web/ui/post-form"
               "cl-blog/web/ui/blog"
               "cl-blog/web/ui/blog-post"
               "cl-blog/web/routes"
               "cl-blog/web/server")
  :description "cl-blog - Common Lisp blog template with HTMX"
  :in-order-to ((test-op (test-op "cl-blog/tests"))))

(defsystem "cl-blog/tests"
  :class :package-inferred-system
  :pathname "tests/"
  :depends-on ("cl-blog"
               "rove"
               "clack-test"
               ;; Test support modules
               "cl-blog/tests/support/db"
               ;; Utils tests
               "cl-blog/tests/utils/common"
               ;; DB tests
               "cl-blog/tests/db/core"
               "cl-blog/tests/db/jsonb"
               "cl-blog/tests/db/users"
               "cl-blog/tests/db/posts"
               ;; Web tests
               "cl-blog/tests/web/auth"
               "cl-blog/tests/web/routes"
               ;; Main test runner
               "cl-blog/tests/all")
  :perform (test-op (o c)
             (unless (symbol-call :cl-blog/tests/all :run-all-tests)
               (error "Some tests failed"))))
