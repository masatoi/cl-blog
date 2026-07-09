# Recurya UI 多言語対応 (i18n) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保存済みユーザー言語設定 (`users.language`) に応じて UI 全体を日本語/英語で描画する i18n レイヤーを導入し、言語混在を解消する。

**Architecture:** 中央メッセージカタログ (`locale → key → template`) を新規 `recurya/web/i18n/*` モジュールに置く。`tr` 関数がリクエスト単位の動的変数 `*locale*` を引き、`format` で補間する。`*locale*` は `bind-locale` Lack ミドルウェアがセッションユーザーの `:language`（匿名/非対応は `:en`）から束縛する。テンプレートのリテラルを `(tr :ns.key ...)` に置換し、フラッシュメッセージは URL 埋め込みからキー渡しへ移行する。

**Tech Stack:** Common Lisp / ASDF `:package-inferred-system` / Ningle + Lack + Spinneret / Rove（`:style :spec`）/ cl-mcp ツール（`load-system` / `run-tests` / `lisp-edit-form` / `repl-eval`）。

**設計仕様:** `docs/superpowers/specs/2026-07-10-i18n-ui-localization-design.md`

---

## 作業上の重要な約束（全タスク共通）

- **Lisp 操作は必ず cl-mcp ツール経由**（`lisp-edit-form` / `lisp-patch-form` / `lisp-read-file` / `load-system` / `run-tests` / `repl-eval`）。`.lisp` / `.asd` に Read/Edit/Write/Grep/Glob を使わない。
- **セッション開始時**: `fs-set-project-root {"path": "."}` を実行。
- **テスト実行**（本プランの "Run" 表記）:
  - ロード: `load-system {"system": "<sys>", "force": true}`
  - スイート実行: `run-tests {"system": "recurya/tests/web/i18n-core"}` のように**テストサブシステム名**を渡す。
- **コミットは頻繁に**。各タスク末尾で `git`（許可コマンド）を使う。ブランチは `feat/i18n-ui-localization`（設計コミット済み）。
- **コンテナ再起動が必要なのは Task 0.4 のみ**（新 ASDF モジュール追加）。以後はホットリロード（`load-system`）。再起動は**ユーザーに依頼**し、完了後 cl-mcp を再接続する（`docs/DEVELOPMENT.md`）。

---

## File Structure

**新規作成:**
- `web/i18n/core.lisp` — `recurya/web/i18n/core`: `*locale*` / `*default-locale*` / `*catalogs*` / `register-message` / `defcatalog` / `tr` / `available-locales` / `normalize-locale` / `known-key-p` / `catalog-keys` / `with-locale` / `bind-locale`。
- `web/i18n/en.lisp` — `recurya/web/i18n/en`: 英語カタログ（基準）。
- `web/i18n/ja.lisp` — `recurya/web/i18n/ja`: 日本語カタログ。
- `tests/web/i18n-core.lisp` — `recurya/tests/web/i18n-core`: `tr` 単体 + `bind-locale` + パリティ検査。
- `tests/web/i18n-catalog.lisp` — `recurya/tests/web/i18n-catalog`: en/ja キーパリティの網羅検査（ファンアウトで育つ安全網）。

**変更:**
- `recurya.asd` — `recurya` 系に i18n 3 系を追加（web/ui・routes・server より前）; `recurya/tests` 系に i18n テスト 2 系を追加。
- `tests/all.lisp` — `*test-packages*` に i18n テストパッケージを追加。
- `web/server.lisp:build-app` — builder に `#'bind-locale` を `:session` 直後へ挿入。
- `web/ui/layout.lisp` / `web/ui/account.lisp` — パイロット変換（Phase 1）。
- `web/routes.lisp:account-update-handler` / `account-page-handler` — フラッシュのキー化（Phase 1）。
- 残り UI ファイル群（Phase 2..N、ファンアウト）。
- `web/ui/novel.lisp` / `web/ui/arena.lisp` — JS 埋め込みテキスト（Phase 終盤）。
- `tests/web/routes.lisp` — ドロップダウン縮小/キー化に伴う既存テスト更新（Phase 1）。
- `docs/DEVELOPMENT.md` — i18n の使い方・言語追加手順を追記（Phase 終盤）。

---

## Phase 0 — i18n 機構

### Task 0.1: `tr` ランタイムと `bind-locale`（コア）

**Files:**
- Create: `web/i18n/core.lisp`
- Test: `tests/web/i18n-core.lisp`

- [ ] **Step 1: コアファイルの雛形を作成**

`fs-write-file` で `web/i18n/core.lisp` を最小内容で作成（以後 `lisp-edit-form` で拡張）:

```lisp
(defpackage #:recurya/web/i18n/core
  (:use #:cl)
  (:export #:*locale* #:*default-locale* #:*catalogs*
           #:register-message #:defcatalog
           #:tr #:available-locales #:normalize-locale
           #:known-key-p #:catalog-keys #:with-locale #:bind-locale))

(in-package #:recurya/web/i18n/core)

(defvar *default-locale* :en
  "対応言語が無い/非対応時のフォールバック言語。")

(defvar *locale* :en
  "現在のリクエストのロケール。BIND-LOCALE が束縛する。")

(defparameter *catalogs* (make-hash-table :test 'eq)
  "locale(keyword) -> (hash-table: key(keyword) -> template(string))。")

(defun %catalog (locale)
  "LOCALE のメッセージ表を返す（無ければ作る）。"
  (or (gethash locale *catalogs*)
      (setf (gethash locale *catalogs*) (make-hash-table :test 'eq))))

(defun register-message (locale key template)
  "LOCALE の KEY に TEMPLATE(string) を登録する。"
  (check-type key keyword)
  (check-type template string)
  (setf (gethash key (%catalog locale)) template)
  key)

(defmacro defcatalog (locale &body pairs)
  "LOCALE に複数メッセージを登録する。各 PAIR は (KEY TEMPLATE)。"
  `(progn
     ,@(loop for (key template) in pairs
             collect `(register-message ,locale ,key ,template))
     ,locale))

(defun available-locales ()
  "登録済みロケールのキーワード一覧。"
  (loop for k being the hash-keys of *catalogs* collect k))

(defun catalog-keys (locale)
  "LOCALE に登録済みのメッセージキー一覧。"
  (let ((cat (gethash locale *catalogs*)))
    (when cat (loop for k being the hash-keys of cat collect k))))

(defun known-key-p (key &optional (locale *locale*))
  "KEY が LOCALE か既定ロケールのカタログに存在すれば真。"
  (flet ((in (loc) (let ((c (gethash loc *catalogs*)))
                     (and c (nth-value 1 (gethash key c))))))
    (or (in locale) (in *default-locale*))))

(defun normalize-locale (designator)
  "DESIGNATOR (\"ja\" / :ja / nil) を対応ロケールキーワードに正規化する。
非対応/空/nil は *DEFAULT-LOCALE* を返す。"
  (let ((kw (cond
              ((keywordp designator) designator)
              ((and (stringp designator) (plusp (length designator)))
               (intern (string-upcase designator) :keyword))
              (t nil))))
    (if (and kw (gethash kw *catalogs*)) kw *default-locale*)))

(defun %lookup (key locale)
  (let ((cat (gethash locale *catalogs*)))
    (when cat (gethash key cat))))

(defun tr (key &rest format-args)
  "KEY を *LOCALE* -> *DEFAULT-LOCALE* -> 可視マーカー の順に引き、
テンプレートに (apply #'format nil template format-args) を適用して返す。"
  (let ((template (or (%lookup key *locale*) (%lookup key *default-locale*))))
    (if template
        (apply #'format nil template format-args)
        (progn
          (warn "i18n: missing message key ~S (locale ~S)" key *locale*)
          (format nil "⟦~A⟧" key)))))

(defmacro with-locale ((locale) &body body)
  "*LOCALE* を (normalize-locale LOCALE) に束縛して BODY を評価。"
  `(let ((*locale* (normalize-locale ,locale))) ,@body))

(defun bind-locale (app)
  "Lack ミドルウェア: セッションユーザーの :language から *LOCALE* を束縛して
下流 APP を呼ぶ。:session の後段で使うこと。"
  (lambda (env)
    (let* ((session (getf env :lack.session))
           (user (and session (gethash :user session)))
           (lang (and user (getf user :language))))
      (let ((*locale* (normalize-locale lang)))
        (funcall app env)))))
```

`lisp-check-parens {"path": "web/i18n/core.lisp"}` で括弧整合を確認。

- [ ] **Step 2: 失敗するテストを書く**

`fs-write-file` で `tests/web/i18n-core.lisp` を作成:

```lisp
(defpackage #:recurya/tests/web/i18n-core
  (:use #:cl #:rove)
  (:import-from #:recurya/web/i18n/core
                #:*locale* #:*default-locale* #:*catalogs*
                #:register-message #:defcatalog #:tr
                #:available-locales #:normalize-locale
                #:known-key-p #:with-locale #:bind-locale))
(in-package #:recurya/tests/web/i18n-core)

;; テスト専用の隔離カタログを使う（本番カタログに依存しない）
(defmacro with-fresh-catalogs (&body body)
  `(let ((*catalogs* (make-hash-table :test 'eq))
         (*default-locale* :en)
         (*locale* :en))
     ,@body))

(deftest tr-lookup-and-fallback
  (with-fresh-catalogs
    (defcatalog :en (:greet "Hello, ~A") (:only-en "EN only"))
    (defcatalog :ja (:greet "こんにちは、~A さん"))
    (testing "現在ロケールで引く"
      (let ((*locale* :ja))
        (ok (string= (tr :greet "太郎") "こんにちは、太郎 さん"))))
    (testing "既定ロケールへフォールバック"
      (let ((*locale* :ja))
        (ok (string= (tr :only-en) "EN only"))))
    (testing "未定義キーは可視マーカー"
      (let ((*locale* :en))
        (ok (search "⟦" (handler-bind ((warning #'muffle-warning)
                                        (t (lambda (c) (declare (ignore c)))))
                          (tr :missing))))))))

(deftest normalize-locale-rules
  (with-fresh-catalogs
    (defcatalog :en (:x "x"))
    (defcatalog :ja (:x "x"))
    (testing "対応する文字列/キーワードはそのまま"
      (ok (eq (normalize-locale "ja") :ja))
      (ok (eq (normalize-locale :en) :en)))
    (testing "非対応/空/nil は既定ロケール"
      (ok (eq (normalize-locale "fr") :en))
      (ok (eq (normalize-locale "") :en))
      (ok (eq (normalize-locale nil) :en)))))

(deftest bind-locale-from-session
  (with-fresh-catalogs
    (defcatalog :en (:x "x")) (defcatalog :ja (:x "x"))
    (labels ((mk-env (lang)
               (let ((sess (make-hash-table :test 'eq)))
                 (when lang
                   (setf (gethash :user sess) (list :id "1" :language lang)))
                 (list :lack.session sess)))
             (probe (env)
               (funcall (bind-locale (lambda (e) (declare (ignore e)) *locale*))
                        env)))
      (testing "ユーザー言語が束縛される"
        (ok (eq (probe (mk-env "ja")) :ja)))
      (testing "匿名は既定ロケール"
        (ok (eq (probe (list :lack.session (make-hash-table :test 'eq))) :en)))
      (testing "非対応言語は既定ロケール"
        (ok (eq (probe (mk-env "fr")) :en))))))
```

- [ ] **Step 3: 失敗を確認**

新規テストサブシステムは Task 0.3 で `.asd` に登録するまで単独ロードできない。ここでは **`repl-eval` で暫定ロード**して失敗を確認する:

Run: `repl-eval {"code": "(progn (load \"web/i18n/core.lisp\") (load \"tests/web/i18n-core.lisp\") (rove:run :recurya/tests/web/i18n-core))"}`
Expected: `recurya/web/i18n/core` はまだ本番ロードパスに無いので、まず core をロード→テストロード→**全 deftest が通る**こと（このタスクは core を同時に書くため PASS になる想定。もし FAIL なら core を修正）。

> TDD 補足: 純粋な RED を見たい場合は Step 1 の各 `defun` 本体を一時的に `(error "todo")` にして Step 3 が FAIL するのを確認してから実装で埋める。

- [ ] **Step 4: テストが通ることを確認**

Run: 同上 `repl-eval`。Expected: `3 tests, N assertions, 0 failures`。

- [ ] **Step 5: コミット**

```bash
git add web/i18n/core.lisp tests/web/i18n-core.lisp
git commit -m "feat(i18n): add tr runtime, locale normalization, bind-locale middleware"
```

---

### Task 0.2: 英語/日本語カタログの初期セット + パリティ検査

**Files:**
- Create: `web/i18n/en.lisp`, `web/i18n/ja.lisp`
- Create: `tests/web/i18n-catalog.lisp`

- [ ] **Step 1: 英語カタログを作成**

`fs-write-file` で `web/i18n/en.lisp`（Phase 1 で使う `common.*` / `layout.*` / `account.*` / `flash.*` を先行投入。値は現行の英語リテラル）:

```lisp
(defpackage #:recurya/web/i18n/en
  (:use #:cl)
  (:import-from #:recurya/web/i18n/core #:defcatalog))
(in-package #:recurya/web/i18n/en)

(defcatalog :en
  ;; --- common ---
  (:common.buttons.save    "Save")
  (:common.buttons.cancel  "Cancel")
  (:common.buttons.add     "Add")
  (:common.buttons.remove  "Remove")
  (:common.buttons.up      "Up")
  (:common.buttons.down    "Down")
  (:common.pagination.prev "← Previous")
  (:common.pagination.next "Next →")
  (:common.pagination.info "Page ~A of ~A")
  ;; --- layout ---
  (:layout.nav.notebooks      "Notebooks")
  (:layout.nav.courses        "Courses")
  (:layout.nav.my_notebooks   "My Notebooks")
  (:layout.nav.my_courses     "My Courses")
  (:layout.menu.account       "Account settings")
  (:layout.menu.logout        "Log out")
  (:layout.auth.badge_anon    "Not signed in")
  (:layout.auth.login         "Login")
  (:layout.auth.account_fallback "Account")
  ;; --- account ---
  (:account.page_title        "Account settings - recurya")
  (:account.heading           "Account settings")
  (:account.subtitle          "Update your profile information or request account deletion.")
  (:account.field.email       "Email")
  (:account.field.display_name "Display name")
  (:account.regional.heading  "Regional settings")
  (:account.regional.language "Language")
  (:account.regional.timezone "Timezone")
  (:account.save              "Save changes")
  (:account.danger.heading    "Danger zone")
  (:account.danger.body       "Deleting your account removes all datasets, features, jobs, and stored files. This action cannot be undone.")
  (:account.danger.delete     "Delete account")
  ;; --- flash ---
  (:flash.account.saved       "Settings updated")
  (:flash.account.name_blank  "Display name cannot be blank"))
```

- [ ] **Step 2: 日本語カタログを作成**

`fs-write-file` で `web/i18n/ja.lisp`（既存日本語 16 件の語調を基準に翻訳。ヘッダーの既存訳「未ログイン/ログイン」を流用）:

```lisp
(defpackage #:recurya/web/i18n/ja
  (:use #:cl)
  (:import-from #:recurya/web/i18n/core #:defcatalog))
(in-package #:recurya/web/i18n/ja)

(defcatalog :ja
  ;; --- common ---
  (:common.buttons.save    "保存")
  (:common.buttons.cancel  "キャンセル")
  (:common.buttons.add     "追加")
  (:common.buttons.remove  "削除")
  (:common.buttons.up      "上へ")
  (:common.buttons.down    "下へ")
  (:common.pagination.prev "← 前へ")
  (:common.pagination.next "次へ →")
  (:common.pagination.info "~A / ~A ページ")
  ;; --- layout ---
  (:layout.nav.notebooks      "ノートブック")
  (:layout.nav.courses        "コース")
  (:layout.nav.my_notebooks   "マイノートブック")
  (:layout.nav.my_courses     "マイコース")
  (:layout.menu.account       "アカウント設定")
  (:layout.menu.logout        "ログアウト")
  (:layout.auth.badge_anon    "未ログイン")
  (:layout.auth.login         "ログイン")
  (:layout.auth.account_fallback "アカウント")
  ;; --- account ---
  (:account.page_title        "アカウント設定 - recurya")
  (:account.heading           "アカウント設定")
  (:account.subtitle          "プロフィール情報の更新、またはアカウント削除の申請ができます。")
  (:account.field.email       "メールアドレス")
  (:account.field.display_name "表示名")
  (:account.regional.heading  "地域設定")
  (:account.regional.language "言語")
  (:account.regional.timezone "タイムゾーン")
  (:account.save              "変更を保存")
  (:account.danger.heading    "危険な操作")
  (:account.danger.body       "アカウントを削除すると、すべてのデータセット・機能・ジョブ・保存ファイルが失われます。この操作は取り消せません。")
  (:account.danger.delete     "アカウントを削除")
  ;; --- flash ---
  (:flash.account.saved       "設定を更新しました")
  (:flash.account.name_blank  "表示名は空にできません"))
```

- [ ] **Step 3: パリティ検査テストを書く（失敗する）**

`fs-write-file` で `tests/web/i18n-catalog.lisp`:

```lisp
(defpackage #:recurya/tests/web/i18n-catalog
  (:use #:cl #:rove)
  (:import-from #:recurya/web/i18n/core #:catalog-keys))
(in-package #:recurya/tests/web/i18n-catalog)

(defun missing-keys (from to)
  "FROM ロケールに在り TO ロケールに無いキー。"
  (set-difference (catalog-keys from) (catalog-keys to)))

(deftest en-ja-parity
  (testing "英語キーはすべて日本語に存在する"
    (let ((miss (missing-keys :en :ja)))
      (ok (null miss) (format nil "ja に欠落: ~S" miss))))
  (testing "日本語キーはすべて英語に存在する"
    (let ((miss (missing-keys :ja :en)))
      (ok (null miss) (format nil "en に欠落: ~S" miss)))))
```

Run: `repl-eval {"code": "(progn (load \"web/i18n/core.lisp\") (load \"web/i18n/en.lisp\") (load \"web/i18n/ja.lisp\") (load \"tests/web/i18n-catalog.lisp\") (rove:run :recurya/tests/web/i18n-catalog))"}`
Expected: PASS（en/ja を対でメンテしていれば緑）。欠落があればここで露見する。

- [ ] **Step 4: 通ることを確認**（Step 3 の Run が緑）

- [ ] **Step 5: コミット**

```bash
git add web/i18n/en.lisp web/i18n/ja.lisp tests/web/i18n-catalog.lisp
git commit -m "feat(i18n): seed en/ja catalogs (common/layout/account/flash) + parity test"
```

---

### Task 0.3: ASDF / テストランナー配線

**Files:**
- Modify: `recurya.asd`
- Modify: `tests/all.lisp`

- [ ] **Step 1: `recurya` 系に i18n を追加**

`lisp-patch-form` で `recurya.asd` の `(defsystem "recurya" ...)` の `:depends-on` リスト内、`;; Web layer` の直後・`"recurya/web/app"` の**前**に 3 行を挿入:

```
old_text:
               ;; Web layer
               "recurya/web/app"
new_text:
               ;; i18n（web/ui・routes・server より前にロード）
               "recurya/web/i18n/core"
               "recurya/web/i18n/en"
               "recurya/web/i18n/ja"
               ;; Web layer
               "recurya/web/app"
```

- [ ] **Step 2: `recurya/tests` 系に i18n テストを追加**

`lisp-patch-form` で `(defsystem "recurya/tests" ...)` の `:depends-on` 内、`;; Web tests` の直後に挿入:

```
old_text:
               ;; Web tests
               "recurya/tests/web/oauth"
new_text:
               ;; Web tests
               "recurya/tests/web/i18n-core"
               "recurya/tests/web/i18n-catalog"
               "recurya/tests/web/oauth"
```

- [ ] **Step 3: `tests/all.lisp` の `*test-packages*` に追加**

`lisp-patch-form` で:

```
old_text:
    :recurya/tests/web/oauth
new_text:
    :recurya/tests/web/i18n-core
    :recurya/tests/web/i18n-catalog
    :recurya/tests/web/oauth
```

- [ ] **Step 4: コミット**

```bash
git add recurya.asd tests/all.lisp
git commit -m "build(i18n): register i18n modules and test suites in ASDF/runner"
```

---

### Task 0.4: `bind-locale` を Lack builder に組込み（要コンテナ再起動）

**Files:**
- Modify: `web/server.lisp:build-app`

- [ ] **Step 1: `server.lisp` に i18n import を追加**

`lisp-patch-form` で `(defpackage #:recurya/web/server ...)` に import を追加:

```
old_text:
  (:import-from #:recurya/web/auth
                #:require-dashboard-auth
                #:require-real-handle)
new_text:
  (:import-from #:recurya/web/auth
                #:require-dashboard-auth
                #:require-real-handle)
  (:import-from #:recurya/web/i18n/core
                #:bind-locale)
```

- [ ] **Step 2: builder に `#'bind-locale` を挿入**

`lisp-patch-form` で `build-app` の builder フォーム内:

```
old_text:
     (:session :store (make-session-store))
     #'require-dashboard-auth
new_text:
     (:session :store (make-session-store))
     ;; セッション確定後に現在ロケールを *locale* へ束縛（全描画をカバー）
     #'bind-locale
     #'require-dashboard-auth
```

- [ ] **Step 3: コンテナ再起動（ユーザー依頼）**

新モジュール（ASDF 構成変更）を取り込むため再起動が必要。**ユーザーに次を依頼**し、完了後に cl-mcp を再接続:

```
docker compose build recurya && docker compose --profile app up -d
```

（`docs/DEVELOPMENT.md`。再起動後は cl-mcp/SLIME 再接続。）

- [ ] **Step 4: フルロードと i18n スイートの確認**

Run: `load-system {"system": "recurya", "force": true}` → 警告 0 を確認。
Run: `run-tests {"system": "recurya/tests/web/i18n-core"}` → PASS。
Run: `run-tests {"system": "recurya/tests/web/i18n-catalog"}` → PASS。

- [ ] **Step 5: コミット**

```bash
git add web/server.lisp
git commit -m "feat(i18n): bind *locale* per-request via bind-locale middleware"
```

---

## Phase 1 — パイロット変換（layout / account）

> このフェーズが**以降のファンアウトの正確なパターン**（リテラル→`tr` 置換、en/ja 登録、`:en`/`:ja` 両ロケールの描画テスト）を確立する。Phase 2..N は本フェーズを手本にする。

### Task 1.1: `layout.lisp` ヘッダー/ナビの i18n 化

**Files:**
- Modify: `web/ui/layout.lisp`（`header` 関数、`get-user-display` フォールバック）
- Test: `tests/web/i18n-render.lisp`（新規）

- [ ] **Step 1: 失敗する描画テストを書く**

`fs-write-file` で `tests/web/i18n-render.lisp`:

```lisp
(defpackage #:recurya/tests/web/i18n-render
  (:use #:cl #:rove)
  (:import-from #:recurya/web/i18n/core #:*locale*))
(in-package #:recurya/tests/web/i18n-render)

(deftest layout-header-localized
  (testing "英語ロケール: 英語ナビ"
    (let ((*locale* :en))
      (let ((html (recurya/web/ui/layout:header nil)))
        (ok (search "Notebooks" html))
        (ok (search "Login" html))
        (ng (search "未ログイン" html)))))
  (testing "日本語ロケール: 日本語ナビ"
    (let ((*locale* :ja))
      (let ((html (recurya/web/ui/layout:header nil)))
        (ok (search "ノートブック" html))
        (ok (search "ログイン" html)))))
  (testing "ログイン済み日本語: メニュー訳"
    (let ((*locale* :ja))
      (let ((html (recurya/web/ui/layout:header
                   (list :name "太郎" :email "t@example.com"))))
        (ok (search "アカウント設定" html))
        (ok (search "ログアウト" html))))))
```

`.asd`（`recurya/tests` の `:depends-on`）と `tests/all.lisp` に `recurya/tests/web/i18n-render` を追記（Task 0.3 と同じ要領、`lisp-patch-form`）。

Run: `run-tests {"system": "recurya/tests/web/i18n-render"}`
Expected: FAIL（`header` はまだ英語リテラルで「ノートブック」「アカウント設定」が無い）。

- [ ] **Step 2: `layout.lisp` に `tr` import を追加**

`lisp-patch-form` で `(defpackage #:recurya/web/ui/layout ...)` に:

```
old_text:
  (:import-from #:recurya/web/ui/csrf
                #:csrf-input
                #:csrf-form-block)
new_text:
  (:import-from #:recurya/web/ui/csrf
                #:csrf-input
                #:csrf-form-block)
  (:import-from #:recurya/web/i18n/core
                #:tr)
```

- [ ] **Step 3: `header` のリテラルを `tr` に置換**

`lisp-patch-form` を用い、`header` 関数内の可視文字列を置換（`"Recurya"` ブランドは据置）:

- `"Notebooks"` → `(tr :layout.nav.notebooks)`
- `"Courses"` → `(tr :layout.nav.courses)`
- `"My Notebooks"` → `(tr :layout.nav.my_notebooks)`
- `"My Courses"` → `(tr :layout.nav.my_courses)`
- `"Account settings"` → `(tr :layout.menu.account)`
- `"Log out"` → `(tr :layout.menu.logout)`
- `"未ログイン"` → `(tr :layout.auth.badge_anon)`
- `"ログイン"` → `(tr :layout.auth.login)`

`get-user-display` の最終フォールバック `"Account"` → `(tr :layout.auth.account_fallback)`。

各置換は `lisp-patch-form {form_type:"defun", form_name:"header", old_text:"\"Notebooks\"", new_text:"(tr :layout.nav.notebooks)"}` の形。曖昧一致を避けるため `old_text` は文脈込み（例 `:href \"/notebooks\" \"Notebooks\")`）で指定する。

- [ ] **Step 4: 再ロードしてテスト緑を確認**

Run: `repl-eval {"code": "(asdf:load-system :recurya/web/ui/layout :force t)"}`
Run: `run-tests {"system": "recurya/tests/web/i18n-render"}`
Expected: PASS。

- [ ] **Step 5: コミット**

```bash
git add web/ui/layout.lisp tests/web/i18n-render.lisp recurya.asd tests/all.lisp
git commit -m "feat(i18n): localize app header/nav; fixes ja/en mix in header"
```

---

### Task 1.2: `account.lisp` 設定画面の i18n 化 + ドロップダウンを available-locales 駆動

**Files:**
- Modify: `web/ui/account.lisp`（`render`、言語 `<select>`）
- Test: `tests/web/i18n-render.lisp`（追記）

- [ ] **Step 1: 失敗するテストを追記**

`lisp-edit-form` で `tests/web/i18n-render.lisp` に `deftest` を追加:

```lisp
(deftest account-page-localized
  (let ((user (list :email "t@example.com" :name "太郎"
                    :language "ja" :timezone "Asia/Tokyo")))
    (testing "日本語ロケールで日本語ラベル"
      (let ((*locale* :ja))
        (let ((html (recurya/web/ui/account:render :user user)))
          (ok (search "アカウント設定" html))
          (ok (search "地域設定" html))
          (ok (search "変更を保存" html)))))
    (testing "言語ドロップダウンは available-locales のみ（fr は出ない）"
      (let ((*locale* :en))
        (let ((html (recurya/web/ui/account:render :user user)))
          (ok (search "English" html))
          (ok (search "日本語" html))
          (ng (search "Français" html)))))))
```

Run: `run-tests {"system": "recurya/tests/web/i18n-render"}` → FAIL。

- [ ] **Step 2: import 追加**

`lisp-patch-form` で `(defpackage #:recurya/web/ui/account ...)` に
`(:import-from #:recurya/web/i18n/core #:tr #:available-locales)` を追加。

- [ ] **Step 3: `render` のリテラルを `tr` に置換**

`lisp-patch-form` で `render` 内を置換:

- page-shell の `:title "Account settings - recurya"` → `(tr :account.page_title)`
- `"Account settings"` → `(tr :account.heading)`
- `"Update your profile..."` → `(tr :account.subtitle)`
- `"Email"` → `(tr :account.field.email)`
- `"Display name"` → `(tr :account.field.display_name)`
- `"Regional settings"` → `(tr :account.regional.heading)`
- `"Language"` → `(tr :account.regional.language)`
- `"Timezone"` → `(tr :account.regional.timezone)`
- `"Save changes"` → `(tr :account.save)`
- `"Danger zone"` → `(tr :account.danger.heading)`
- `"Deleting your account..."` → `(tr :account.danger.body)`
- `"Delete account"` → `(tr :account.danger.delete)`

- [ ] **Step 4: 言語 `<select>` を available-locales 駆動に変更**

`lisp-patch-form` で言語ドロップダウンの `dolist` を、`*languages*` を `available-locales` で絞り込む形へ:

```
old_text:
                        (dolist (lang *languages*)
                          (let ((code (car lang)) (label (cdr lang)))
                            (if (string= code language)
                                (:option :value code :selected t label)
                                (:option :value code label))))
new_text:
                        (dolist (lang *languages*)
                          (let ((code (car lang)) (label (cdr lang)))
                            (when (member (intern (string-upcase code) :keyword)
                                          (available-locales))
                              (if (string= code language)
                                  (:option :value code :selected t label)
                                  (:option :value code label)))))
```

（`*languages*` のエンドニム表示名はそのまま。対応ロケールのみ出力。）

- [ ] **Step 5: 再ロードしてテスト緑を確認**

Run: `repl-eval {"code": "(asdf:load-system :recurya/web/ui/account :force t)"}`
Run: `run-tests {"system": "recurya/tests/web/i18n-render"}` → PASS。

- [ ] **Step 6: コミット**

```bash
git add web/ui/account.lisp tests/web/i18n-render.lisp
git commit -m "feat(i18n): localize account settings; drive language select from available-locales"
```

---

### Task 1.3: フラッシュメッセージのキー化 + 既存テスト更新

**Files:**
- Modify: `web/routes.lisp`（`account-update-handler`、`account-page-handler`）
- Modify: `tests/web/routes.lisp`（既存テスト更新）

- [ ] **Step 1: フラッシュ・ホワイトリストと解決ヘルパを追加**

`lisp-edit-form` で `web/routes.lisp` に、`account-page-handler` の直前へ新規フォームを挿入:

```lisp
(defparameter *flash-message-keys*
  '(("account.saved"      . :flash.account.saved)
    ("account.name_blank" . :flash.account.name_blank))
  "許可されたフラッシュキー(URLトークン) -> カタログキー。任意キー注入を防ぐ。")

(defun resolve-flash (token)
  "URL クエリの TOKEN をホワイトリスト経由で翻訳文に解決。未許可/nil は nil。"
  (let ((catalog-key (cdr (assoc token *flash-message-keys* :test #'equal))))
    (when catalog-key
      (recurya/web/i18n/core:tr catalog-key))))
```

`(defpackage #:recurya/web/routes ...)` に `(:import-from #:recurya/web/i18n/core)` を追加（`tr` は package 修飾で呼ぶか import する。ここでは `resolve-flash` 内で package 修飾使用のため import 不要だが、明示 import を推奨）。

- [ ] **Step 2: `account-update-handler` のリダイレクトをキー渡しに変更**

`lisp-patch-form` で:

```
old_text:  (redirect "/account?error=Display+name+cannot+be+blank")
new_text:  (redirect "/account?err=account.name_blank")
```
```
old_text:  (redirect "/account?message=Settings+updated")
new_text:  (redirect "/account?msg=account.saved")
```

- [ ] **Step 3: `account-page-handler` でキーを翻訳して render に渡す**

`lisp-patch-form` で `account-page-handler` を、`params` からトークンを読み解決する形へ:

```
old_text:
  (declare (ignore params))
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (html-response (recurya/web/ui/account:render :user user)))))
new_text:
  (let ((user (get-current-user)))
    (if (null user)
        (redirect "/login")
        (let ((message (resolve-flash (get-param params "msg")))
              (error   (resolve-flash (get-param params "err"))))
          (html-response
           (recurya/web/ui/account:render :user user
                                          :message message :error error))))))
```

（`account:render` は既に `:message`/`:error` を受け取る。）

- [ ] **Step 4: 既存テストを新方式に更新**

`tests/web/routes.lisp` の以下を更新（`lisp-patch-form`）:

- `account-update-persists-to-database` / `account-update-saves-*`: リダイレクト先 assert を `?message=Settings` → `?msg=account.saved`、`?error=` → `?err=account.name_blank` に変更。
- `account-page-displays-saved-settings`: 言語を `"fr"` で保存し `"value=fr selected"` を期待している箇所を、**対応ロケールの `"ja"`** に変更（`value=ja selected`）。timezone 部分は据置。
  - 具体: params の `("language" . "fr")` → `("language" . "ja")`、assert `"value=fr selected"` → `"value=ja selected"`、コメントの French → Japanese。

- [ ] **Step 5: 再ロードして関連テスト緑を確認**

Run: `repl-eval {"code": "(asdf:load-system :recurya/web/routes :force t)"}`
Run（DB 必須。PostgreSQL:15434 起動前提）: `run-tests {"system": "recurya/tests/web/routes"}`
Expected: PASS（フラッシュ/ドロップダウン更新分を含む）。

- [ ] **Step 6: request-test.sh でパイロット E2E スモーク**

`scripts/request-test.sh` に、(a) 日本語ユーザーで `/account` を GET し「地域設定」「変更を保存」を含む、(b) 設定更新後のリダイレクトが `?msg=account.saved` で遷移先に「設定を更新しました」を含む、のチェックブロックを追加して実行。

- [ ] **Step 7: コミット**

```bash
git add web/routes.lisp tests/web/routes.lisp scripts/request-test.sh
git commit -m "feat(i18n): key-based localized flash messages for account settings"
```

---

## Phase 2..N — 残り UI のファンアウト変換

**対象と規模（棚卸し順、chrome 文字列数）:** reference(67), routes(残り≈34), course-form(29), notebook-form(27), courses(24), notebooks-dashboard(20), notebook(19), arena(15), login(10), puzzle(10), course-list(9), errors(9), wardlisp-home(9), onboarding(8), playground(8), course(7), notebook-list(7), profile(4), routes-wardlisp(2), novel(1)。

各ファイルは **Phase 1 と同一の手順**（＝本プランで完全に示した手本）で変換する。以下の**per-file 手順**を各対象に適用し、**1 ファイル = 1 チェックボックス**で進捗管理する。

### per-file 変換手順（各ファイル共通・Phase 1 が実例）

1. `lisp-read-file {path, collapsed:false}` で対象を読む。棚卸しの該当エントリ（`/tmp/.../tasks/w2ikdpb88.output` の `perFileRaw`）で対象文字列を突合。
2. パッケージに `(:import-from #:recurya/web/i18n/core #:tr)` を追加。共通語を使う場合は既存 `common.*` を優先。
3. 可視リテラルを `(tr :ns.key ...args)` へ置換（`lisp-patch-form`、`old_text` は文脈込みで一意化）。名前空間は仕様 3.5 準拠（`notebooks.* / notebook.* / courses.* / course.* / wardlisp.* / errors.* / onboarding.* / auth.login.* / profile.* / novel.* / server.errors.*`）。
4. `web/i18n/en.lisp` に英語（＝除去したリテラル）を、`web/i18n/ja.lisp` に日本語訳を **defcatalog に追記**（`lisp-edit-form`）。
5. **要注意点の遵守（仕様 3.5）**:
   - `format` テンプレート（`~A`/`~D`/`~:P`）は**プレースホルダごとカタログに格納**し `(tr :key args...)`。ja テンプレートは `~:P` を省く。
   - インライン `<code>` 周りの分割文言は **Spinneret で DOM 構造を保ち文言だけ tr**（`:raw` でカタログ HTML を出さない）。ユーザーデータは別ノードで自動エスケープ。
   - ブランド語/プロバイダ名（recurya/Google/GitHub）は据置。
   - `<title>`/`<h1>` に補間されるユーザー生成コンテンツ（notebook/course タイトル、`@handle`）は**翻訳しない**。
   - reference.lisp の型名等（Integer/Symbol/Fuel/Cons…）は翻訳者判断で原語可（**レビュー対象**）。`<pre><code>` 内は対象外。
6. `repl-eval {"code": "(asdf:load-system :<system> :force t)"}` で再ロード。
7. **描画テスト**を `tests/web/i18n-render.lisp` に追記（`:ja` で代表的日本語文字列を含む／`:en` で英語を含む）。DB 不要なら render 直呼び、DB 必須なら該当 `tests/web/*` を利用。
8. `run-tests {"system": "recurya/tests/web/i18n-catalog"}`（パリティ）＋当該 render テスト → 緑。
9. コミット: `git commit -m "feat(i18n): localize <file>"`。

### 日本語訳のドラフト（エージェント→レビュー）

- 342 件の日本語訳は **Workflow でファンアウト・ドラフト**する（1 ファイル＝1 エージェント: 該当英語文字列＋名前空間を受け取り、`(key en ja)` の三つ組を返す）。既存日本語 16 件を語調の基準として全エージェントに渡す。
- ドラフト集約後、**ユーザーがカタログ（ja）をレビュー**。承認された訳のみ `web/i18n/ja.lisp` に反映する。
- 訳語の一貫性（例: notebook=ノートブック、course=コース、cell=セル、run=実行、submit=提出）を用語集としてワークフローのプロンプトに固定する。

### ファンアウト・チェックリスト（1 ファイル = 1 完了単位）

- [ ] `web/ui/reference.lisp`（67）＋ `wardlisp.reference.*`（型名はレビュー対象）
- [ ] `web/routes.lisp` 残り（≈34）＋ `server.errors.*`（Forbidden/Unauthorized/Not found/Bad request/Invalid index/Index out of range/Cannot run this cell/`db-save-error-message`）
- [ ] `web/ui/course-form.lisp`（29）＋ `courses.form.*`
- [ ] `web/ui/notebook-form.lisp`（27）＋ `notebooks.form.* / notebook.cheatsheet.*`（`*cheatsheet-text*` の混在文言を en/ja へ分離）
- [ ] `web/ui/courses.lisp`（24）＋ `courses.dashboard.* / common.visibility.*`
- [ ] `web/ui/notebooks-dashboard.lisp`（20）＋ `notebooks.dashboard.* / common.actions.* / common.visibility.*`
- [ ] `web/ui/notebook.lisp`（19）＋ `notebook.view.* / notebook.cell.*`（既存日本語含む）
- [ ] `web/ui/arena.lisp`（15）＋ `wardlisp.arena.*`（JS 埋め込み `Turn ` は Phase 終盤 F.1 で対応）
- [ ] `web/ui/login.lisp`（10）＋ `auth.login.*`（dev-stub バナーの分割文言を再結合）
- [ ] `web/ui/puzzle.lisp`（10）＋ `wardlisp.puzzle.*`
- [ ] `web/ui/course-list.lisp`（9）＋ `courses.list.* / common.pagination.*`（`~:P` プラールに注意）
- [ ] `web/ui/errors.lisp`（9）＋ `errors.*`（404/500/400 数字は据置、CSRF 既存日本語を ja へ）
- [ ] `web/ui/wardlisp-home.lisp`（9）＋ `wardlisp.home.*`
- [ ] `web/ui/onboarding.lisp`（8）＋ `onboarding.*`（`<code>suggested-handle</code>` 周辺の分割文言に注意）
- [ ] `web/ui/playground.lisp`（8）＋ `wardlisp.playground.*`
- [ ] `web/ui/course.lisp`（7）＋ `course.view.*`（タイトル補間は非翻訳）
- [ ] `web/ui/notebook-list.lisp`（7）＋ `notebooks.list.* / common.pagination.*`
- [ ] `web/ui/profile.lisp`（4）＋ `profile.*`（`@handle` 補間は非翻訳）
- [ ] `web/routes-wardlisp.lisp`（2）
- [ ] `web/ui/novel.lisp`（1、JS 埋め込み `— おわり —` は F.1 で対応）

---

## Phase 終盤 — 仕上げ

### Task F.1: JS 埋め込み可視テキストの i18n 化

**Files:**
- Modify: `web/ui/novel.lisp`（`render-player` の終端メッセージ）、`web/ui/arena.lisp`（`render-result` の `Turn ` ラベル）
- Test: 既存 node テスト（`docs/DEVELOPMENT.md` 参照）＋描画 attr assert

- [ ] **Step 1: 失敗テスト（attr 存在）** — `tests/web/i18n-render.lisp` に、`:ja` で novel/arena の描画に `data-*` 属性（例 `data-end-label`）が正しい訳文で出力されることを assert。Run → FAIL。
- [ ] **Step 2: 実装** — Lisp 側で `(tr :novel.end)` / `(tr :wardlisp.arena.turn_label)` を `data-end-label` / `data-turn-label` 属性でレンダリング。インライン `<script>` を、直書き文字列 `— おわり —` / `"Turn "` の代わりに `element.dataset.endLabel` / `dataset.turnLabel` を読む形へ変更。
- [ ] **Step 3: en/ja カタログに `:novel.end`（en "— The End —" / ja "— おわり —"）、`:wardlisp.arena.turn_label`（en "Turn " / ja "ターン "）を追加。**
- [ ] **Step 4: 再ロード＋描画テスト＋node テスト** → PASS。
- [ ] **Step 5: コミット** `git commit -m "feat(i18n): localize JS-embedded novel/arena labels via data-* attrs"`

### Task F.2: 残存フラッシュ/URL 埋め込みテキストのキー化スイープ

**Files:** `web/routes.lisp` ほか
- [ ] **Step 1:** `clgrep-search {pattern:"\\?(message|error)=", path:"web"}` で残存の URL 埋め込み可視テキストを洗い出す。
- [ ] **Step 2:** 各所を `*flash-message-keys*` に追加し（キー＋en/ja カタログ）、`?msg=`/`?err=` トークン方式へ移行。遷移先ハンドラで `resolve-flash`。
- [ ] **Step 3:** 該当ハンドラテストのリダイレクト assert を更新。
- [ ] **Step 4:** Run 関連 `run-tests` → PASS。
- [ ] **Step 5:** コミット。

### Task F.3: 全体グリーン + E2E スモーク

- [ ] **Step 1:** `repl-eval {"code": "(asdf:compile-system :recurya :force t)"}` → 警告 0。
- [ ] **Step 2:** `run-tests {"system": "recurya/tests/web/i18n-catalog"}` → **パリティ緑（訳し漏れ 0）**。
- [ ] **Step 3:** `run-tests {"system": "recurya/tests"}`（PostgreSQL:15434 起動）→ 全緑。既存の英語リテラル依存テストが赤なら `*locale*=:en` 前提へ更新。
- [ ] **Step 4:** `scripts/request-test.sh` を en/ja 両ユーザーで実行し、主要導線（ヘッダー/ダッシュボード/ノートブック閲覧/コース/アカウント）が各言語で描画されることをスモーク確認。
- [ ] **Step 5:** node テスト（CodeMirror/JS）→ PASS。

### Task F.4: ドキュメント整備

**Files:** `docs/DEVELOPMENT.md`
- [ ] **Step 1:** i18n の使い方（`tr` 呼び出し規約、名前空間、`format` テンプレート、`:raw` 禁止ルール、`data-*` での JS 連携）と、**言語追加手順**（`web/i18n/<lang>.lisp` を追加→`.asd`/`tests` 登録→パリティ緑）を追記。
- [ ] **Step 2:** コミット `git commit -m "docs: document i18n usage and how to add a language"`。

---

## Self-Review（計画→仕様の照合）

- **対応言語 ja/en・拡張容易** → Task 0.1/0.2（per-locale カタログファイル、`available-locales`）✓
- **ログイン=設定言語 / 匿名=英語** → Task 0.1 `normalize-locale` + 0.4 `bind-locale`（匿名 nil→`:en`）✓
- **名前空間キー + common.* 重複排除** → Task 0.2 seed + Phase 2 の名前空間規約 ✓
- **アカウント設定のみ（スイッチャー無し）** → 追加 UI 無し。ドロップダウンは available-locales 駆動（Task 1.2）✓
- **フラッシュのキー化** → Task 1.3 + F.2 ✓
- **342 件 tr 化 / エージェント下書き→レビュー** → Phase 2 ファンアウト + ドラフト・ワークフロー + ユーザーレビュー ✓
- **format テンプレート / 分割文言 / JS 埋め込み / ブランド / 既存日本語16 / エンドニム / reference 技術用語 / ユーザーコンテンツ非翻訳** → per-file 手順 Step 5 + Task F.1 に明記 ✓
- **パリティ検査でCI落とす** → Task 0.2 + F.3 Step 2 ✓
- **描画/E2E テスト・既存テスト更新** → Task 1.1/1.2/1.3 + F.3 ✓
- **ASDF 新モジュール→再起動** → Task 0.4 Step 3 ✓
