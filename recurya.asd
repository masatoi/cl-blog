(defsystem "recurya"
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
               ;; WardLisp language (external library)
               "wardlisp"
               ;; Game logic
               "recurya/game/puzzle"
               "recurya/game/puzzles/adjacent"
               "recurya/game/puzzles/contains"
               "recurya/game/puzzles/nearest-point"
               "recurya/game/puzzles/safe-moves"
               "recurya/game/puzzles/choose-action"
               "recurya/game/puzzles/registry"
               ;; Arena
               "recurya/game/arena"
               "recurya/game/scenario"
               ;; Shared utilities
               "recurya/utils/common"
               ;; Database layer
               "recurya/db/core"
               "recurya/db/jsonb"
               "recurya/db/users"
               "recurya/db/posts"
               "recurya/db"
               ;; Models
               "recurya/models/users"
               "recurya/models/post"
               ;; Web layer
               "recurya/web/app"
               "recurya/web/auth"
               "recurya/web/ui/styles"
               "recurya/web/ui/layout"
               "recurya/web/ui/login"
               "recurya/web/ui/signup"
               "recurya/web/ui/errors"
               "recurya/web/ui/account"
               ;; Blog UI
               "recurya/web/ui/posts"
               "recurya/web/ui/post-form"
               "recurya/web/ui/blog"
               "recurya/web/ui/blog-post"
               "recurya/web/routes"
               ;; WardLisp UI
               "recurya/web/ui/wardlisp-home"
               "recurya/web/ui/editor"
               "recurya/web/ui/puzzle"
               "recurya/web/ui/arena"
               "recurya/web/ui/playground"
               "recurya/web/ui/reference"
               "recurya/web/routes-wardlisp"
               "recurya/web/server")
  :description "Recurya - Lisp learning game web system"
  :in-order-to ((test-op (test-op "recurya/tests"))))

(defsystem "recurya/tests"
  :class :package-inferred-system
  :pathname "tests/"
  :depends-on ("recurya"
               "rove"
               "clack-test"
               ;; Test support modules
               "recurya/tests/support/db"
               ;; Utils tests
               "recurya/tests/utils/common"
               ;; DB tests
               "recurya/tests/db/core"
               "recurya/tests/db/jsonb"
               "recurya/tests/db/users"
               "recurya/tests/db/posts"
               ;; Web tests
               "recurya/tests/web/auth"
               "recurya/tests/web/routes"
               ;; Game tests
               "recurya/tests/game/puzzle"
               "recurya/tests/game/arena"
               ;; WardLisp integration tests
               "recurya/tests/wardlisp-integration"
               ;; Main test runner
               "recurya/tests/all")
  :perform (test-op (o c)
             (unless (symbol-call :recurya/tests/all :run-all-tests)
               (error "Some tests failed"))))
