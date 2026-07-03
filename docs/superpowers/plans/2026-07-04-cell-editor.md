# セル単位エディタ + CodeMirror 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ノートブック編集フォームを、フェンス付き単一テキストエリアから、セル単位の CodeMirror エディタに刷新する（サーバー・保存形式は不変）。

**Architecture:** 案A。サーバーは編集フォームに既存 `cells`(構造化) を `data-cells` JSON で埋め込み、従来の `<textarea name="body">` も残す。`cell-editor.js` がセルエディタを構築し、送信時に全セルを既存フェンス形式の `body` へ組み立てて hidden textarea に書き戻す。サーバー/パーサー/DB保存は無変更。

**Tech Stack:** Common Lisp (Ningle/Spinneret), CodeMirror 5 (CDN), vanilla JS。参照: `docs/superpowers/specs/2026-07-04-cell-editor-design.md`。

---

## 前提知識（実装者向け）

- **cell 構造** (`game/notebook.lisp`): `cell` は `:id :kind :body :description :test-cases`。kind は `:prose :code-eval :code-exercise :code-solution :scene`。
- **フェンス形式** (`game/notebook-parser.lisp` の `cells->body-md`): セル間は空行1つ(`\n\n`)、末尾改行なし。
  - prose→`===prose===\n<body>`, eval→`===eval===\n<body>`, solution→`===solution: <desc>===\n<body>`, scene→`===scene===\n<body>`
  - exercise→`===exercise: <desc>===\n<body>` + 各 test-case `===expect[: <desc>]===\n<expect-body>`
  - test-case body: input非空なら `input: <i>\noutput: <o>`、そうでなければ期待値単一行
- **cells の JSONB 形** (`game/notebook-jsonb.lisp` の `cell->jsonb-form`): DB の `notebook.cells` 列。`notebook-cells-parsed`(`db/notebooks.lisp`) で Lisp データに戻せる。
- **既存の編集導線**: `notebook-edit-handler` / `notebook-new-handler` (`web/routes.lisp`) → `recurya/web/ui/notebook-form:render`。
- **cl-mcp 必須**: `.lisp`/`.asd` は `lisp-edit-form`/`lisp-read-file`/`load-system`/`run-tests` を使う。テストDBは分離済み（`run-tests` は本番に触れない）。

---

## Task 1: サーバーが編集フォームへ cells(JSON) を渡す

**Files:**
- Modify: `web/routes.lisp`（`notebook-edit-handler`, `notebook-new-handler`, 必要なら cells 取得ヘルパー）
- Modify: `web/ui/notebook-form.lisp`（`render` に `:cells` 引数追加、`data-cells` 埋め込み）
- Test: `tests/web/notebook-routes.lisp`

- [ ] **Step 1: 失敗するテストを書く** — 編集フォームのレスポンス body に `data-cells` 属性（cells の JSON）が含まれることを検証。

```lisp
;; tests/web/notebook-routes.lisp に追加（既存の mk-user / with-mock-session を利用）
(deftest notebook-edit-form-embeds-cells-json
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook!
                :title "N" :slug "n"
                :body-md (format nil "===prose===~%hello~%~%===eval===~%(+ 1 2)")
                :cells nil :status "draft" :visibility "private" :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let ((body (first (response-body
                            (notebook-edit-handler (list (cons :id id)))))))
          (ok (search "data-cells=" body) "edit form embeds data-cells")
          (ok (search "prose" body) "cells JSON mentions prose kind")
          (ok (search "code-eval" body) "cells JSON mentions eval kind"))))))
```

- [ ] **Step 2: テストを実行して失敗を確認**

`run-tests` system=`recurya/tests/web/notebook-routes` test=`recurya/tests/web/notebook-routes::notebook-edit-form-embeds-cells-json`
Expected: FAIL（`data-cells=` が無い）

- [ ] **Step 3: cells を取得して render に渡す実装**

`notebook-edit-handler` で、notebook の cells を取得（`notebook-cells-parsed` が使えればそれ、なければ `parse-notebook-body` で body-md から導出）し、`notebook->plist` の結果に `:cells`（`cell->jsonb-form` 相当の JSON 化可能な plist 群）を含めて `notebook-form:render` に渡す。`notebook-new-handler` は `:cells nil`（空）を渡す。`render` は `:cells` を受け取り、cells の JSON を `data-cells` 属性へ出力する最小実装を入れる（JSON化はプロジェクトの JSON エンコーダ `recurya/utils/common` の API を使用。実キー名は実装時に実データで確認）。

- [ ] **Step 4: テストを実行して成功を確認** — `run-tests` … Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add web/routes.lisp web/ui/notebook-form.lisp tests/web/notebook-routes.lisp
git commit -m "feat: embed notebook cells JSON in the edit form"
```

---

## Task 2: 編集フォームに CodeMirror アセットと cell-editor マウントポイントを追加

**Files:**
- Modify: `web/ui/notebook-form.lisp`（CodeMirror CDN リンク、`cell-editor.js` 読込、`<div id="cell-editor-root" data-cells=...>`）
- Test: `tests/web/notebook-routes.lisp`

- [ ] **Step 1: 失敗するテストを書く**

```lisp
(deftest notebook-edit-form-loads-codemirror-and-editor-js
  (with-test-db
    (let* ((user (mk-user))
           (dao (get-user-by-id (getf user :id)))
           (nb (create-notebook! :title "N" :slug "n"
                :body-md (format nil "===prose===~%hi")
                :cells nil :status "draft" :visibility "private" :author dao))
           (id (princ-to-string (notebook-id nb))))
      (with-mock-session (make-session :user user)
        (let ((body (first (response-body
                            (notebook-edit-handler (list (cons :id id)))))))
          (ok (search "codemirror" body) "loads CodeMirror from CDN")
          (ok (search "/static/js/cell-editor.js" body) "loads cell-editor.js")
          (ok (search "id=cell-editor-root" body) "has editor mount point"))))))
```

- [ ] **Step 2: 実行して失敗を確認** — Expected: FAIL
- [ ] **Step 3: 実装** — `page-shell` の `:head-extras` に CodeMirror5 の CSS/JS（core + mode/markdown + mode/scheme, unpkg）を、`:body-scripts` に `/static/js/cell-editor.js` を追加。フォーム内に `<div id="cell-editor-root" data-cells="<JSON>">` を置き、既存 `<textarea name="body">` はそのまま（JS が隠す）。
- [ ] **Step 4: 実行して成功を確認** — Expected: PASS
- [ ] **Step 5: コミット** — `git commit -m "feat: load CodeMirror and cell-editor assets in the notebook form"`

---

## Task 3: cell-editor.js — セル→フェンス body 組み立て（純粋関数）

**Files:**
- Create: `resources/static/js/cell-editor.js`
- Test: `resources/static/js/cell-editor.test.mjs`（node 実行）。JS ランナーが無ければ Task 5 の Lisp 突き合わせで代替。

- [ ] **Step 1: 失敗するテストを書く** — `cellsToBody(cells)` が `cells->body-md` と同じフェンス文字列を返す。

```js
// resources/static/js/cell-editor.test.mjs
import { cellsToBody } from './cell-editor.js';
import assert from 'node:assert';

const cells = [
  { kind: 'prose', body: 'Intro.' },
  { kind: 'code-eval', body: '(+ 1 2)' },
  { kind: 'code-exercise', description: 'sum', body: '; ?',
    testCases: [{ description: 'sum', input: '', output: '3' }] },
  { kind: 'code-solution', description: 'sq', body: '(define (sq x) (* x x))' },
];
const expected =
  '===prose===\nIntro.\n\n' +
  '===eval===\n(+ 1 2)\n\n' +
  '===exercise: sum===\n; ?\n\n===expect: sum===\n3\n\n' +
  '===solution: sq===\n(define (sq x) (* x x))';
assert.strictEqual(cellsToBody(cells), expected);
console.log('ok');
```

- [ ] **Step 2: 実行して失敗を確認** — `node resources/static/js/cell-editor.test.mjs` → FAIL（未定義）
- [ ] **Step 3: 実装** — `cell-editor.js` に `export function cellsToBody(cells)` を実装。design §7 の規則を厳密に：セル間 `\n\n`、末尾改行なし、exercise は本体の後に各 test-case を `\n\n===expect[: desc]===\n<expect-body>` で連結、expect-body は input 非空なら2行、そうでなければ output 単一行。scene は `===scene===\n<body>`。
- [ ] **Step 4: 実行して成功を確認** — `node …` → `ok`
- [ ] **Step 5: コミット** — `git commit -m "feat: cellsToBody fence serializer matching cells->body-md"`

---

## Task 4: cell-editor.js — セルUI構築・CodeMirror・操作・送信

**Files:**
- Modify: `resources/static/js/cell-editor.js`

- [ ] **Step 1: DOM 構築** — `DOMContentLoaded` で `#cell-editor-root` を読み、`data-cells` JSON をパース。cells が空なら prose セル1つで開始。各セルを描画する `renderCell(cell)`：種別セレクタ(prose/eval/exercise/solution)、exercise/solution はタイトル入力、CodeMirror エディタ（prose→markdown, code系→scheme, scene→plain）、exercise は test-cases（input/output 行の追加/削除）。従来 `<textarea name="body">` を `style.display='none'`。
- [ ] **Step 2: セル操作** — ツールバーに「+ セル追加」（種別選択）。各セルに ↑ / ↓ / 削除。並べ替えは配列操作 + 再描画（CodeMirror インスタンスは保持配列で管理）。
- [ ] **Step 3: 送信フック** — フォーム submit 時に、全セルの現在値(CodeMirror `getValue()` 含む)から `cells` 配列を作り、`cellsToBody(cells)` を hidden `body` textarea に代入してから通常送信。
- [ ] **Step 4: フォールバック** — スクリプト冒頭で `window.CodeMirror` が無ければ何もしない（従来 textarea が表示のまま）。全体を try/catch し、失敗時は textarea を復帰。
- [ ] **Step 5: 手動確認 + コミット** — ブラウザで新規/編集を開き、セル分割表示・ハイライト・追加/削除/並べ替え・保存を確認。`git commit -m "feat: cell editor UI with CodeMirror and submit assembly"`

---

## Task 5: Lisp⇔JS フェンス一致の突き合わせ検証 + 手動E2E

**Files:**
- Modify: `resources/static/js/cell-editor.test.mjs`（代表 cells で比較）

- [ ] **Step 1** — 代表 cells（prose/eval/exercise+複数expect/solution/scene 混在）を定義。
- [ ] **Step 2** — Lisp 側 `cells->body-md` の出力を `repl-eval` で取得し固定文字列としてテストへ。
- [ ] **Step 3** — JS `cellsToBody` が同一文字列を返すことを assert。差異があれば Task 3 を修正。
- [ ] **Step 4** — 手動E2E: 新規作成→保存→編集で開き直し→内容一致（ラウンドトリップ）をブラウザで確認。JS 無効時に従来 textarea で編集できることも確認。
- [ ] **Step 5: コミット** — `git commit -m "test: verify JS/Lisp fence serialization parity"`

---

## Self-Review 結果

- **Spec coverage**: §4 案A→Task1-2, §5.1→Task1-2, §5.2→Task3-4, §5.3→Task2, §5.4→Task4 Step4, §7→Task3, §9→Task5。全カバー。
- **未確定の実装ディテール**: (a) cells の JSON エンコーダの正確な関数名（`utils/common` の JSON API を実装時に確認）、(b) `notebook-cells-parsed` の戻り形と `cell->jsonb-form` の JSON キー名（`kind`/`body`/`description`/`test-cases` の JSON 表現）を Task1 実装時に実データで確認し、JS 側キー名を合わせる。
- **型整合**: JS の cell キー（`kind, body, description, testCases{input,output,description}`）は、Task1 でサーバーが出力する `data-cells` の JSON キーと一致させること（サーバー側の JSON キーに JS を合わせる）。
