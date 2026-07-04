# exercise 複数行 Markdown 説明文 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `code-exercise` の説明文を複数行 Markdown で記述できるようにする。フェンスに `===code===` サブフェンスを導入し説明文をブロック化、編集エディタは説明文を Markdown ハイライト付き CodeMirror で編集する。

**Architecture:** exercise フェンスを `===exercise===\n<md desc>\n===code===\n<code>` に変更（旧 `===exercise: <desc>===` は後方互換で受理、シリアライザは常に新形式）。パーサーは `===code===`(`:code-delim`) で説明/コードを分割。JS/Lisp シリアライザを新形式に揃え（byte 一致パリティ）。編集エディタは exercise の説明を prose と同じ markdown CM6 で編集（cell に2つ目の view `descView`）。読者ページは既に Markdown 済みで CSS 微調整のみ。

**Tech Stack:** Common Lisp（cl-ppcre/Spinneret/3bmd）, vanilla JS（CodeMirror 6）, Rove, node。参照 spec: `docs/superpowers/specs/2026-07-04-exercise-multiline-description.md`。

---

## 🔴 環境・前提（全実装/レビュー サブエージェントに必須）

- cl-mcp は稼働中 dev サーバーと同一 Lisp プロセスにインライン実行。**`load-system` は必ず `force=true`（FASL保持=安全）。`clear_fasls:true` 絶対禁止**（string-case FUN-INFO 違反でイメージ破損）。検証は **`run-tests`（テストDB分離）**。
- **`.lisp`/`.asd` は cl-mcp ツールのみ**（`lisp-read-file`/`lisp-edit-form`/`lisp-patch-form`/`load-system`/`run-tests`、Read/Edit/Write/Grep 禁止）。最初に `fs-set-project-root {"path":"/home/wiz/recurya"}`。
- **`.js`/`.mjs` は通常の Read/Write/Edit + `node`**。JS 純関数はトップレベルで DOM に触れない（node import を壊さない）。ブラウザ副作用は `if (typeof document !== 'undefined')` ガード内。
- `repl-eval` は純関数（パーサー/シリアライザ）のみ。稼働中グローバル DB 接続は叩かない。
- Lisp 変更後は該当システムを `load-system force=true` → `run-tests`。struct 再定義/stale package name-conflict が出たら `clear_fasls` 不使用で `load-system` 段階実行 or `repl-eval` で `unintern`/CONTINUE restart（過去タスクで前例あり）。

## 前提知識（実装者向け）

- **パーサー** (`game/notebook-parser.lisp`, package `recurya/game/notebook-parser`):
  - `parse-fence-header (line)` → `(values KIND DESC GATED-P)`。`===prose===`/`===eval===`/`===scene===` は `string=` 判定、exercise/solution/expect は正規表現。
  - `parse-notebook-body (body-md &optional existing-cells)` → `(values CELLS ERRORS)`。状態機械: `current-kind`/`current-desc`/`current-gated-p`/`current-buffer` が収集中セル、`pending-exercise-cell` が exercise（test-cases 収集用）、`in-expect-p`/`expect-desc`/`expect-buffer` が expect ブロック。`close-exercise-body`/`flush-current`/`flush-pending-exercise`/`finalise-expect` が labels。`push-error (line-no msg)`、`buffer-string (buf)` はトリム。
  - `render-cell (stream cell)` が1セルをフェンス出力（ecase）。`cells->body-md` が連結。`render-cell-prose-html` は 3bmd Markdown→サニタイズ HTML。
  - 現状 exercise: ヘッダ `===exercise: <desc>===`（desc必須 `(.+)`）、bare `===exercise===` は `+bare-exercise-header-regex+` で即エラー。
- **JS** (`resources/static/js/cell-editor.js`): `renderCell(cell)` が `${renderCellHeader(cell)}\n${body}` + test-cases。`renderCellHeader(cell)` が kind→ヘッダ。`cellsToBody` が map/join。`buildTitleInput(cell)` が exercise/solution の単一行「Title」入力（`cell.description` バインド）。`buildEditorMount`/`editorExtensionsForKind(kind, cm)`（prose→`[basicSetup, ...markdownExtensions(cm), oneDark]`, code→scheme）。`markdownExtensions(cm)` は markdown StreamParser+HighlightStyle。`syncAllViewsToState`/`destroyAllViews`（cell.view を扱う）。`emptyCell(kind)`/`serverCellToState`/`stateCellToServer`（`view: null` を持つ）。`buildCellItemDom(editorState, cell, index)` がセル DOM。
- **reader** (`web/ui/notebook.lisp`): `render-code-cell` が exercise の `(cell-description cell)` を `render-cell-prose-html` でレンダリングし `.cell__desc` に表示。`*styles*` の `.cell__desc` に `white-space: pre-wrap`。

---

## Task 1: パーサーが新 exercise 形式（`===exercise===`/`===code===`）をパース

**Files:**
- Modify: `game/notebook-parser.lisp`（`parse-fence-header`、状態機械、`close-exercise-body`）
- Test: `tests/game/notebook-parser.lisp`

- [ ] **Step 1: 失敗するテストを書く** — `tests/game/notebook-parser.lisp` に追加（`make-cell`/`cell-*`/`parse-notebook-body` は利用可能）。

```lisp
(deftest parse-exercise-new-form-splits-desc-and-code
  (testing "===exercise===/===code=== splits a multi-line description from code"
    (let ((c (first (parse-notebook-body
                     (format nil "===exercise===~%line1~%line2~%===code===~%(fill)~%~%===expect===~%3")))))
      (ok (eq :code-exercise (cell-kind c)))
      (ok (string= (format nil "line1~%line2") (cell-description c)))
      (ok (string= "(fill)" (cell-body c)))
      (ok (= 1 (length (cell-test-cases c)))))))

(deftest parse-exercise-old-form-still-works
  (testing "the old ===exercise: desc=== header form still parses (backward compat)"
    (let ((c (first (parse-notebook-body
                     (format nil "===exercise: sum===~%(fill)~%~%===expect===~%3")))))
      (ok (eq :code-exercise (cell-kind c)))
      (ok (string= "sum" (cell-description c)))
      (ok (string= "(fill)" (cell-body c))))))

(deftest parse-exercise-empty-desc-allowed-with-code
  (testing "bare ===exercise=== + ===code=== with an empty description is allowed"
    (let ((c (first (parse-notebook-body
                     (format nil "===exercise===~%===code===~%(fill)")))))
      (ok (eq :code-exercise (cell-kind c)))
      (ok (string= "" (cell-description c)))
      (ok (string= "(fill)" (cell-body c))))))

(deftest parse-exercise-malformed-emits-errors
  (testing "malformed exercise forms emit validation errors"
    (flet ((errs (body)
             (multiple-value-bind (cells e) (parse-notebook-body body)
               (declare (ignore cells)) e)))
      ;; bare exercise, no ===code===
      (ok (some (lambda (e) (search "requires a description" (getf e :message)))
                (errs (format nil "===exercise===~%(fill)"))))
      ;; header desc AND ===code=== both present
      (ok (some (lambda (e) (search "already set" (getf e :message)))
                (errs (format nil "===exercise: d===~%desc~%===code===~%(fill)"))))
      ;; ===code=== outside an exercise
      (ok (some (lambda (e) (search "only valid inside an exercise" (getf e :message)))
                (errs (format nil "===prose===~%hi~%~%===code===~%x")))))))
```

- [ ] **Step 2: 実行して失敗を確認** — `load-system recurya/game/notebook-parser force=true` + tests force=true → `run-tests` 上記4テスト。Expected: FAIL（`===exercise===`/`===code===` 未対応）。

- [ ] **Step 3a: `parse-fence-header` に新ヘッダを追加** — `lisp-edit-form` で `parse-fence-header` を置換。先頭 `cond` の `===scene===` の直後に2行追加:
```lisp
    ((string= line "===exercise===") (values :code-exercise nil nil))
    ((string= line "===code===")     (values :code-delim nil nil))
```
（他分岐は不変。docstring に `:code-exercise` の bare 形式と `:code-delim` を追記してよい。）

- [ ] **Step 3b: 状態機械に `:code-delim` 処理と header-line 追跡を追加** — `lisp-read-file name_pattern="parse-notebook-body"` で現物確認のうえ `lisp-edit-form` で置換:
  1. `let` の状態変数に `(current-header-line nil)` を追加。
  2. `close-exercise-body` を、`current-desc` nil（bare かつ `===code===` 未出現）ならエラー、非 nil なら従来通りセル生成、に変更:
```lisp
             (close-exercise-body ()
               (when (eq current-kind :code-exercise)
                 (if (null current-desc)
                     (push-error current-header-line
                                 "===exercise=== requires a description or a ===code=== block")
                     (let ((body (buffer-string current-buffer))
                           (desc current-desc))
                       (multiple-value-bind (matched-id new-remaining)
                           (take-matching-cell-id :code-exercise body desc
                                                  remaining-existing)
                         (setf remaining-existing new-remaining)
                         (setf pending-exercise-cell
                               (make-cell :id (or matched-id
                                                  (princ-to-string (uuid:make-v4-uuid)))
                                          :kind :code-exercise
                                          :body body
                                          :description desc
                                          :test-cases nil)))))
                 (setf (fill-pointer current-buffer) 0
                       current-kind nil
                       current-desc nil
                       current-gated-p nil
                       current-header-line nil)))
```
  3. `flush-current` のリセット節にも `current-header-line nil` を追加。
  4. dispatch の `cond` で、`:expect` 節の**直後**に `:code-delim` 節を追加（`(kind ...)` の前）:
```lisp
            ;; ===code=== : split the exercise description from the code stub.
            ((eq kind :code-delim)
             (cond
               ((not (eq current-kind :code-exercise))
                (push-error line-number
                            "===code=== is only valid inside an exercise"))
               ((not (null current-desc))
                (push-error line-number
                            "unexpected ===code=== (the description is already set)"))
               (t
                (setf current-desc (buffer-string current-buffer)
                      (fill-pointer current-buffer) 0))))
```
  5. `(kind ...)` 節（recognised header）で `current-kind` 等をセットする箇所に `current-header-line line-number` を追加:
```lisp
             (setf current-kind kind
                   current-desc desc
                   current-gated-p gated
                   current-header-line line-number)
```
  6. **bare-exercise エラー節を削除**: `((cl-ppcre:scan +bare-exercise-header-regex+ line) (push-error ...))` の clause を削除（bare `===exercise===` は 3a で `:code-exercise` を返すため `(kind ...)` に入る）。不要になった `+bare-exercise-header-regex+` defparameter も削除してよい。

- [ ] **Step 4: リロードして成功を確認** — `load-system recurya/game/notebook-parser force=true` → tests force=true → `run-tests` 上記4テスト（PASS）＋ `run-tests recurya/tests/game/notebook-parser`（**全体緑**、既存パーサーテスト・solution 系のリグレッションなし）。

- [ ] **Step 5: コミット**
```bash
git add game/notebook-parser.lisp tests/game/notebook-parser.lisp
git commit -m "feat: parse ===exercise===/===code=== multi-line exercise descriptions"
```

---

## Task 2: Lisp シリアライザが新形式を出力 + ラウンドトリップ

**Files:**
- Modify: `game/notebook-parser.lisp`（`render-cell` の exercise 分岐）
- Test: `tests/game/notebook-parser.lisp`

- [ ] **Step 1: 失敗するテストを書く**
```lisp
(deftest exercise-multiline-desc-serializes-and-round-trips
  (testing "an exercise serializes to the ===exercise===/===code=== block form and round-trips"
    (let* ((cells (list (make-cell :kind :code-exercise
                                   :description (format nil "para1~%~%para2")
                                   :body "(fill)"
                                   :test-cases (list (make-test-case :input "" :expected "3"
                                                                     :description "")))))
           (md (cells->body-md cells)))
      ;; new block form is emitted
      (ok (search "===exercise===" md))
      (ok (search "===code===" md))
      (ng (search "===exercise: " md) "no old-style header desc")
      ;; round-trip preserves the multi-line description and body
      (let ((c2 (first (parse-notebook-body md))))
        (ok (string= (format nil "para1~%~%para2") (cell-description c2)))
        (ok (string= "(fill)" (cell-body c2)))
        (ok (= 1 (length (cell-test-cases c2))))))))
```

- [ ] **Step 2: 実行して失敗を確認** — `run-tests` 上記。Expected: FAIL（`render-cell` が旧 `===exercise: desc===` を出力）。

- [ ] **Step 3: 実装** — `lisp-patch-form` で `render-cell` の `ecase` の `:code-exercise` 行を置換。現在:
```lisp
      (:code-exercise (format stream "===exercise: ~A===" desc))
```
置換後:
```lisp
      (:code-exercise (format stream "===exercise===~%~A~%===code===" desc))
```
（ecase 節が「ヘッダ相当」を書き、後続の共通処理 `(write-char #\Newline stream) (write-string body stream)` がそのまま body を続けるので、全体で `===exercise===\n<desc>\n===code===\n<body>` になる。test-case 連結は不変。`cells->body-md` の docstring も新形式に更新してよい。）

- [ ] **Step 4: リロードして成功を確認** — `load-system` parser force=true → tests force=true → `run-tests` 上記 + `recurya/tests/game/notebook-parser`（全体緑）。

- [ ] **Step 5: コミット**
```bash
git add game/notebook-parser.lisp tests/game/notebook-parser.lisp
git commit -m "feat: serialize exercises in the ===exercise===/===code=== block form"
```

---

## Task 3: JS シリアライザが新形式を出力 + Lisp パリティ（node）

**Files:**
- Modify: `resources/static/js/cell-editor.js`（`renderCell` の exercise 分岐）
- Test: `resources/static/js/cell-editor.test.mjs`

- [ ] **Step 1: 失敗するテストを書く** — `cell-editor.test.mjs` 末尾に追加:
```js
// Exercise cells serialize to the ===exercise===/===code=== block form, with a
// multi-line Markdown description, matching Lisp cells->body-md.
{
  const md = cellsToBody([{
    'cell-id': '', kind: 'code-exercise',
    description: 'para1\n\npara2', body: '(fill)',
    'test-cases': [{ input: '', expected: '3', description: '' }],
  }]);
  assert.strictEqual(
    md,
    '===exercise===\npara1\n\npara2\n===code===\n(fill)\n\n===expect===\n3');
}
console.log('ok: exercise serializes to ===exercise===/===code=== block form');
```

- [ ] **Step 2: 実行して失敗を確認** — `node resources/static/js/cell-editor.test.mjs`。Expected: FAIL（renderCell が旧 `===exercise: desc===` を出力）。

- [ ] **Step 3: 実装** — `renderCell` を exercise 特別扱いに（Read で現物確認のうえ）:
```js
function renderCell(cell) {
  const body = cell.body ?? '';
  let rendered;
  if (cell.kind === 'code-exercise') {
    const description = cell.description ?? '';
    rendered = `===exercise===\n${description}\n===code===\n${body}`;
  } else {
    rendered = `${renderCellHeader(cell)}\n${body}`;
  }

  if (cell.kind === 'code-exercise') {
    const rawTestCases = cell['test-cases'];
    const testCases = Array.isArray(rawTestCases) ? rawTestCases : [];
    for (const testCase of testCases) {
      rendered += '\n\n' + renderTestCase(testCase);
    }
  }
  return rendered;
}
```
（`renderCellHeader` の `code-exercise` 分岐は renderCell が特別扱いするため未使用になる。残しても害はないが、JSDoc に「exercise は renderCell が直接組み立てる」と注記してよい。）

- [ ] **Step 4: 実行して成功を確認** — `node resources/static/js/cell-editor.test.mjs`（全 `ok`、既存パリティ・gated・markdown テスト維持）+ `node --check resources/static/js/cell-editor.js`。

  加えて **Lisp とのパリティを実測**（controller/実装者、`repl-eval` は純関数で安全）: `(recurya/utils/common:json->string (recurya/game/notebook-parser:cells->body-md (list (recurya/game/notebook:make-cell :kind :code-exercise :description (format nil "para1~%~%para2") :body "(fill)" :test-cases (list (recurya/game/puzzle:make-test-case :input "" :expected "3" :description ""))))))` の出力（JSONエンコード済み文字列）が、上記 JS の期待値 `===exercise===\npara1\n\npara2\n===code===\n(fill)\n\n===expect===\n3` と一致することを確認。差異があれば JS を Lisp に合わせる。

- [ ] **Step 5: コミット**
```bash
git add resources/static/js/cell-editor.js resources/static/js/cell-editor.test.mjs
git commit -m "feat: JS cellsToBody emits the exercise ===code=== block form"
```

---

## Task 4: 編集UI — exercise 説明文を Markdown ハイライト CM6 で編集

**Files:**
- Modify: `resources/static/js/cell-editor.js`

- [ ] **Step 1: 実装（DOM/CM。node で DOM テスト不可のためロジックを注意深く）** — Read で `buildEditorMount`/`editorExtensionsForKind`/`markdownExtensions`/`syncAllViewsToState`/`destroyAllViews`/`emptyCell`/`serverCellToState`/`stateCellToServer`/`buildCellItemDom`/`buildTitleInput` を確認のうえ:

  1a. **`descView` を state 形状に追加**: `emptyCell` の返却に `descView: null` を追加。`serverCellToState` の返却に `descView: null` を追加。`stateCellToServer` は変更不要（view/descView は送らない）。

  1b. **`buildDescriptionEditor(editorState, cell)` を新設**（`buildEditorMount` の近くに。prose と同じ markdown extensions を再利用）:
```js
/**
 * Mount a Markdown-highlighted CodeMirror editor for a code-exercise cell's
 * description (the problem statement), storing the view on `cell.descView`.
 * Reuses the prose Markdown extensions.
 *
 * @param {object} editorState
 * @param {object} cell
 * @returns {HTMLDivElement}
 */
function buildDescriptionEditor(editorState, cell) {
  const wrap = document.createElement('div');
  wrap.className = 'cell-editor-field cell-editor-desc';
  const label = document.createElement('div');
  label.className = 'cell-editor-desc-label';
  label.textContent = 'Description (Markdown)';
  wrap.appendChild(label);

  const mount = document.createElement('div');
  mount.className = 'cell-editor-cm-mount';
  wrap.appendChild(mount);

  const { EditorView, EditorState } = editorState.cmModules;
  const extensions = editorExtensionsForKind('prose', editorState.cmModules);
  const view = new EditorView({
    state: EditorState.create({ doc: cell.description ?? '', extensions }),
    parent: mount,
  });
  cell.descView = view;
  return wrap;
}
```

  1c. **`buildCellItemDom` の title-input 分岐を kind で分ける**: `code-exercise` のとき `buildTitleInput` の代わりに `buildDescriptionEditor(editorState, cell)` を appendChild、`code-solution` のときは従来通り `buildTitleInput(cell)`。現物の該当条件分岐（title を出している箇所）に合わせて置換。

  1d. **`syncAllViewsToState`**: 各 cell で `cell.view` を body に吸い上げる既存処理に加え、`if (cell.descView) cell.description = cell.descView.state.doc.toString();` を追加。

  1e. **`destroyAllViews`**: `cell.view` の destroy に加え、`if (cell.descView) { cell.descView.destroy(); cell.descView = null; }` を追加。

- [ ] **Step 2: 回帰確認** — `node resources/static/js/cell-editor.test.mjs`（全 `ok`、トップレベル DOM 非依存維持＝`buildDescriptionEditor` は関数定義のみ）+ `node --check resources/static/js/cell-editor.js`。

- [ ] **Step 3: 手動確認メモ** — ブラウザ実機は controller 側。実装者は「exercise セルの説明が Markdown ハイライト CM6 になり、`cell.description` にバインドされ、再描画（renderAll）で descView が吸い上げ→destroy→再生成される」ことをコード上で保証したと報告。solution は単一行 Title のままであることも。

- [ ] **Step 4: コミット**
```bash
git add resources/static/js/cell-editor.js
git commit -m "feat: edit exercise descriptions in a Markdown-highlighted editor"
```

---

## Task 5: reader の `.cell__desc` CSS 微調整

**Files:**
- Modify: `web/ui/notebook.lisp`（`*styles*` の `.cell__desc`）
- Test: `tests/web/notebook-routes.lisp`

- [ ] **Step 1: 失敗するテストを書く** — 複数行 Markdown 説明文の exercise が読者ページで段落として描画されることを検証。既存の公開ノートブックテスト（`public-notebook-by-handle-handler`、`:cells (mapcar #'recurya/web/routes::cell->jsonb-form (recurya/game/notebook-parser:parse-notebook-body body))` の積み方）に合わせる:
```lisp
(deftest exercise-multiline-description-renders-as-markdown
  (testing "a multi-line Markdown exercise description renders as HTML paragraphs"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (handle (users-handle dao))
             (body (format nil "===exercise===~%para one~%~%para two~%===code===~%(fill)~%~%===expect===~%3"))
             (nb (create-notebook! :title "N" :slug "n" :body-md body
                                   :cells (mapcar #'recurya/web/routes::cell->jsonb-form
                                                  (recurya/game/notebook-parser:parse-notebook-body body))
                                   :status "published" :visibility "public"
                                   :published-at (local-time:now) :author dao))
             (slug (recurya/db/notebooks:notebook-slug nb)))
        (declare (ignorable nb))
        (with-mock-session (make-session)
          (let ((page (first (response-body
                              (public-notebook-by-handle-handler
                               (list (cons :captures (list handle slug))))))))
            (ok (search "para one" page))
            (ok (search "para two" page))
            ;; 3bmd renders two paragraphs => two <p> in the description
            (ok (search "<p>" page) "description is rendered as Markdown HTML")))))))
```
（captures/`create-notebook!` は既存テストに厳密に合わせる。上記は指針。）

- [ ] **Step 2: 実行して失敗を確認** — `run-tests` 上記テスト。もし既にパス（description が既に Markdown レンダリング済みのため段落は出る）なら、CSS 変更のみが目的なので Step 1 のテストは「回帰ガード」として残し Step 3 の CSS 変更へ進む。Expected: おそらく PASS（描画は既存機能）。※このタスクはテストで担保しづらい CSS 変更が主。テストが最初から緑なら、それを回帰ガードとして残す。

- [ ] **Step 3: CSS 変更** — `lisp-read-file name_pattern` で `*styles*` を確認し、`.cell__desc { ... white-space: pre-wrap; ... }` の `white-space: pre-wrap;` を `white-space: normal;` に `lisp-patch-form` で変更（レンダリング済み Markdown HTML 段落向け）。

- [ ] **Step 4: リロードして確認** — `load-system recurya/web/ui/notebook force=true` → tests force=true → `run-tests recurya/tests/web/notebook-routes`（全体緑）。

- [ ] **Step 5: コミット**
```bash
git add web/ui/notebook.lisp tests/web/notebook-routes.lisp
git commit -m "style: render multi-line exercise descriptions as Markdown paragraphs"
```

---

## Task 6: 全体回帰 + 最終レビュー + finishing-a-development-branch

**Files:** なし（検証のみ）

- [ ] **Step 1: 全 Lisp テスト** — `run-tests recurya/tests`。Expected: 全 PASS。
- [ ] **Step 2: 全 node テスト** — `node resources/static/js/cell-editor.test.mjs`（全 `ok`）+ `node --check`。
- [ ] **Step 3: 最終 code review**（実装全体、`main..HEAD`）— エンドツーエンド（editor 説明→cellsToBody→parse→jsonb→reader）の整合、Lisp⇔JS パリティ、後方互換（旧 exercise）、エラー処理、descView ライフサイクル。
- [ ] **Step 4: 手動 E2E（controller/ユーザー）** — ブラウザで:
  1. exercise セルの説明が Markdown ハイライト CM6 で編集でき、複数行/段落が書ける。
  2. 保存→読者ページで説明が Markdown 段落として表示。
  3. 保存→再編集で説明（複数行）が保持（ラウンドトリップ）。
  4. 既存 exercise（旧形式）が編集で開け、保存で新形式に移行しても内容不変。
- [ ] **Step 5: finishing-a-development-branch** で統合方法を提示。

---

## Self-Review 結果

- **Spec coverage**: §3→Task1/2/3, §4→Task1, §5→Task2/3, §6→Task4, §7→Task5, §9→各テスト+Task6。全カバー。
- **型/形式整合**: 新形式 `===exercise===\n<desc>\n===code===\n<body>` を Lisp `render-cell`（Task2）と JS `renderCell`（Task3）が同一に出力（Task3 Step4 で実測パリティ）。パーサー（Task1）が同形式を desc/body に分割。`:code-delim` センチネルは Lisp 内部のみ。
- **後方互換**: 旧 `===exercise: <desc>===` は Task1 で受理（Test で担保）。既存ノートは再保存で新形式へ移行。
- **未確定の現物依存**: (a) `parse-notebook-body` 状態機械の現物（Task1 Step3b、`lisp-read-file` で確認）、(b) `buildCellItemDom` の title 分岐位置（Task4、Read で確認）、(c) reader テストの captures 形（Task5、既存テスト参照）。いずれもテストで担保。
