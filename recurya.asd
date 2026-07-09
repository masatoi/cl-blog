;;;; Map external package names to their ASDF systems so that
;;;; package-inferred-system can resolve `(:import-from #:clack.test ...)`
;;;; into the `clack-test` system. Without this, ASDF would search for a
;;;; system literally named `clack.test` and fail.
(asdf:register-system-packages "clack-test" '(:clack.test))

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
               ;; DB-backed session store (persists logins across restarts).
               ;; System name differs from its package
               ;; (lack/middleware/session/store/dbi).
               "lack/session/store/dbi"
               "spinneret"
               "ironclad"
               "babel"
               "hunchentoot"
               "cl-ppcre"
               "dexador"
               ;; WardLisp language (external library)
               "wardlisp"
               ;; Markdown + HTML sanitizer for user-authored notebooks
               "3bmd"
               "plump"
               ;; Game logic
               "recurya/game/puzzle"
               "recurya/game/puzzles/adjacent"
               "recurya/game/puzzles/contains"
               "recurya/game/puzzles/nearest-point"
               "recurya/game/puzzles/safe-moves"
               "recurya/game/puzzles/choose-action"
               "recurya/game/puzzles/sqrt2-newton"
               "recurya/game/puzzles/registry"
               ;; Notebook
               "recurya/game/notebook"
               "recurya/game/notebook-parser"
               "recurya/game/novel/interpreter"
               "recurya/game/novel/value"
               "recurya/game/novel/eval"
               "recurya/game/notebook-jsonb"
               ;; Arena
               "recurya/game/arena"
               "recurya/game/scenario"
               ;; Shared utilities
               "recurya/utils/common"
               "recurya/utils/html-sanitize"
               "recurya/utils/handle"
               ;; Database layer
               "recurya/db/core"
               "recurya/db/jsonb"
               "recurya/db/users"
               "recurya/db/notebooks"
               "recurya/db/courses"
               "recurya/utils/access-control"
               "recurya/db/course-notebooks"
               "recurya/db/learn"
               "recurya/db/novel"
               "recurya/db"
               ;; Models
               "recurya/models/users"
               "recurya/models/notebook"
               "recurya/models/course"
               "recurya/models/course-notebook"
               "recurya/models/learn-progress"
               "recurya/models/learn-cell-code"
               "recurya/models/learn-submission"
               "recurya/models/novel-state"
               ;; i18n（web/ui・routes・server より前にロード）
               "recurya/web/i18n/core"
               "recurya/web/i18n/en"
               "recurya/web/i18n/ja"
               ;; Web layer
               "recurya/web/app"
               "recurya/web/auth"
               "recurya/web/ui/styles"
               "recurya/web/ui/csrf"
               "recurya/web/ui/layout"
               "recurya/web/ui/login"
               "recurya/web/ui/errors"
               "recurya/web/ui/account"
               "recurya/web/ui/onboarding"
               "recurya/web/ui/notebook-form"
               "recurya/web/ui/notebooks-dashboard"
               "recurya/web/ui/courses"
               "recurya/web/ui/course-form"
               "recurya/web/ui/notebook-list"
               "recurya/web/ui/course"
               "recurya/web/ui/course-list"
               "recurya/web/ui/profile"
               "recurya/web/routes"
               ;; WardLisp UI
               "recurya/web/ui/wardlisp-home"
               "recurya/web/ui/notebook"
               "recurya/web/ui/novel"
               "recurya/web/ui/editor"
               "recurya/web/ui/puzzle"
               "recurya/web/ui/arena"
               "recurya/web/ui/playground"
               "recurya/web/ui/reference"
               "recurya/web/routes-wardlisp"
               "recurya/web/routes-novel"
               "recurya/web/server"
               ;; Seed / bootstrap
               "recurya/seed/official-content")
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
               "recurya/tests/utils/html-sanitize"
               "recurya/tests/utils/handle"
               "recurya/tests/utils/access-control"
               ;; DB tests
               "recurya/tests/db/core"
               "recurya/tests/db/jsonb"
               "recurya/tests/db/users"
               "recurya/tests/db/notebooks"
               "recurya/tests/db/courses"
               "recurya/tests/db/course-notebooks"
               "recurya/tests/db/learn"
               "recurya/tests/db/novel"
               ;; Web tests
               "recurya/tests/web/i18n-core"
               "recurya/tests/web/i18n-catalog"
               "recurya/tests/web/oauth"
               "recurya/tests/web/onboarding"
               "recurya/tests/web/routes"
               "recurya/tests/web/notebook-routes"
               "recurya/tests/web/course-routes"
               "recurya/tests/web/profile"
               "recurya/tests/web/learn-routes"
               "recurya/tests/web/csrf"
               "recurya/tests/web/dashboard-auth"
               "recurya/tests/web/novel-routes"
               ;; Game tests
               "recurya/tests/game/puzzle"
               "recurya/tests/game/arena"
               "recurya/tests/game/notebook"
               "recurya/tests/game/notebook-parser"
               ;; Novel engine tests
               "recurya/tests/game/novel/interpreter"
               "recurya/tests/game/novel/value"
               "recurya/tests/game/novel/eval"
               ;; Integration tests
               "recurya/tests/integration/sicp-canonical-solutions"
               "recurya/tests/integration/sicp-seed"
               "recurya/tests/integration/novel-sample"
               "recurya/tests/integration/novel-recursion-lesson"
               ;; WardLisp integration tests
               "recurya/tests/wardlisp-integration"
               ;; Main test runner
               "recurya/tests/all")
  :perform (test-op (o c)
             (unless (symbol-call :recurya/tests/all :run-all-tests)
               (error "Some tests failed"))))
