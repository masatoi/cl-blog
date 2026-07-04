# solution セル表示モード（gated 解答）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `code-solution` セルを読者ページで `<details>` として表示できるようにし、著者がセル単位で「常時折りたたみ」か「直前の演習に正解後のみ解放」を選べるようにする（正解後モードは HTMX で即時解放、未解放時は解答本文を HTML に出さない）。

**Architecture:** `cell` 構造体に真偽フィールド `gated` を追加し、フェンス `===solution-locked: <desc>===` としてエンコード（既存 `===solution:===` と後方互換）。パーサー／シリアライザ／JSONB／JS パイプライン／編集UI／読者描画／実行ハンドラに配線。読者描画は `gated` と合格状態（直前 exercise の cell-id が `*passed-cells*` にあるか）でロック/解放を分岐。exercise の Run が `:pass` を返した時に対象 solution を out-of-band swap で即時解放。

**Tech Stack:** Common Lisp（Spinneret/HTMX/cl-ppcre/jzon）, vanilla JS（CodeMirror は無関係）, Rove, node。参照 spec: `docs/superpowers/specs/2026-07-04-solution-cell-reveal-modes.md`。

---

## 🔴 環境・前提（全実装/レビュー サブエージェントに必須）

- この環境の cl-mcp は稼働中の dev Web サーバーと同一 Lisp プロセスにインライン実行される。**`load-system clear_fasls:true` や第三者依存の強制再コンパイルは禁止**（string-case の FUN-INFO 不変条件違反でイメージを不可逆破損）。リロードは **`load-system force=true`（FASL 保持=安全）**、検証は **`run-tests`（テスト DB 分離）**。
- **`.lisp`/`.asd` は cl-mcp ツールのみ**（`lisp-read-file`/`lisp-edit-form`/`lisp-patch-form`/`load-system`/`run-tests`、Read/Edit/Write/Grep 禁止）。最初に `fs-set-project-root {"path":"/home/wiz/recurya"}`。
- **`.js`/`.mjs` は通常の Read/Write/Edit + `node`**。JS の純関数はトップレベルで DOM に触れない（node import を壊さない）。
- **`repl-eval` を稼働中グローバル DB 接続に対して実行しない**（web リクエストと競合しワーカーがハング）。純関数（パーサー・シリアライザ）の repl-eval は安全。
- Lisp 変更後は該当システムを `load-system force=true` でリロードしてから `run-tests`。

## 前提知識（実装者向け）

- **cell 構造** (`game/notebook.lisp`): `defstruct cell` は `id kind body description test-cases`。kind は `:prose :code-eval :code-exercise :code-solution :scene`。
- **フェンス形式** (`game/notebook-parser.lisp`): `parse-fence-header` がヘッダ行→`(values KIND DESC)`。`cells->body-md`/`render-cell` が cells→フェンス文字列。solution は `===solution: <desc>===`。
- **JSONB 形** (`game/notebook-jsonb.lisp`): `cell->jsonb-form`（cell→hash、キーは `"cell-id" "kind" "body" "description" "test-cases"`）/`jsonb-hash->cell`（逆）。
- **読者描画** (`web/ui/notebook.lisp`): `render` が全体、`render-cell (cell index nb-id)` が `ecase` で分岐。`*passed-cells*`（合格 cell-id 文字列リスト）を動的束縛済み。現状 `:code-solution` は空 hidden `.notebook-code`（`codes[]=""`）のみ描画。
- **実行ハンドラ** (`web/routes.lisp`): `%run-public-cell` が採点し `render-cell-result` を返す。`:code-solution`/`:prose` は実行禁止。
- **JS パイプライン** (`resources/static/js/cell-editor.js`): `cellsToBody`/`renderCell`/`renderCellHeader`/`serverCellToState`/`stateCellToServer`/`emptyCell`、編集UIは `buildCellItemDom`/`buildTitleInput`。node テストは `cell-editor.test.mjs`。
- **JSON**: `recurya/utils/common:json->string` / `parse-json`。

---

## Task 1: `cell` 構造体に `gated` フィールドを追加

**Files:**
- Modify: `game/notebook.lisp`（`defstruct cell` に `gated`、export `cell-gated`）
- Test: `tests/game/notebook.lisp`

- [ ] **Step 1: 失敗するテストを書く** — `tests/game/notebook.lisp` に追加。テストパッケージの `:import-from #:recurya/game/notebook` に `#:cell-gated` を追加（無ければ）。

```lisp
(deftest cell-gated-field
  (testing "cell has a boolean gated field defaulting to nil"
    (ok (null (cell-gated (make-cell :kind :code-solution))))
    (ok (eq t (cell-gated (make-cell :kind :code-solution :gated t))))))
```

- [ ] **Step 2: 実行して失敗を確認** — `run-tests` system=`recurya/tests/game/notebook` test=`recurya/tests/game/notebook::cell-gated-field`。Expected: FAIL（`cell-gated` 未定義 or `:gated` 不明キー）。

- [ ] **Step 3: 実装** — `game/notebook.lisp` の `defstruct cell` に `(gated nil :type boolean)` を追加。`defpackage` の `:export` に `#:cell-gated` を追加。`lisp-edit-form` で `defstruct cell` を置換（既存フィールドを保持し末尾に `(gated nil :type boolean)` を追加）。

```lisp
(defstruct cell
  "A single notebook cell. KIND is one of :prose, :code-eval, :code-exercise,
   :code-solution, :scene. BODY is a Spinneret DSL list for :prose cells, or a
   source string for code cells. GATED (only meaningful for :code-solution)
   hides the solution until the preceding exercise is passed."
  (id nil :type (or null keyword string))
  (kind nil :type keyword)
  body
  (description "" :type string)
  (test-cases nil :type list)
  (gated nil :type boolean))
```

- [ ] **Step 4: リロードして成功を確認** — `load-system` system=`recurya/game/notebook` force=true → `load-system` system=`recurya/tests/game/notebook` force=true → `run-tests` 同 test。Expected: PASS。

- [ ] **Step 5: コミット**

```bash
git add game/notebook.lisp tests/game/notebook.lisp
git commit -m "feat: add boolean gated field to notebook cell struct"
```

---

## Task 2: パーサーが `===solution-locked:===` を認識

**Files:**
- Modify: `game/notebook-parser.lisp`（`+solution-locked-header-regex+`、`parse-fence-header` 3値化、`parse-notebook-body` 配線）
- Test: `tests/game/notebook-parser.lisp`

- [ ] **Step 1: 失敗するテストを書く** — `tests/game/notebook-parser.lisp` に追加（`parse-notebook-body`, `cell-kind`, `cell-gated`, `cell-description` が利用可能なこと。無ければ import 追加）。

```lisp
(deftest parse-solution-locked-sets-gated
  (testing "===solution-locked: desc=== yields a gated code-solution cell"
    (let* ((body (format nil "===solution-locked: ans===~%(define x 1)"))
           (cells (parse-notebook-body body))
           (c (first cells)))
      (ok (eq :code-solution (cell-kind c)))
      (ok (eq t (cell-gated c)))
      (ok (string= "ans" (cell-description c)))
      (ok (string= "(define x 1)" (cell-body c))))))

(deftest parse-solution-plain-is-not-gated
  (testing "===solution: desc=== yields a non-gated code-solution cell"
    (let* ((body (format nil "===solution: ans===~%(define x 1)"))
           (c (first (parse-notebook-body body))))
      (ok (eq :code-solution (cell-kind c)))
      (ok (null (cell-gated c))))))
```

- [ ] **Step 2: 実行して失敗を確認** — `run-tests` system=`recurya/tests/game/notebook-parser` tests=`[...::parse-solution-locked-sets-gated, ...::parse-solution-plain-is-not-gated]`。Expected: FAIL（`solution-locked` が未知ヘッダ→cell 化されない/gated 無し）。

- [ ] **Step 3a: 正規表現を追加** — `lisp-edit-form` で `+solution-header-regex+` の直後に挿入。

```lisp
(defparameter +solution-locked-header-regex+
  (cl-ppcre:create-scanner "^===solution-locked: (.+)===$")
  "Scanner for `===solution-locked: <description>===' fence headers, marking a
gated solution (revealed only after the preceding exercise is passed).")
```

- [ ] **Step 3b: `parse-fence-header` を3値化** — `lisp-edit-form` で `parse-fence-header` を置換。solution-locked を solution の前に判定（`solution:` は `solution-locked:` に前方一致しないので順不同でも安全だが、明示のため locked を先に）。全 return を `(values KIND DESC GATED-P)` に統一（既存 return は3値目 nil を追加）。

```lisp
(defun parse-fence-header (line)
  "If LINE is a fence header line, return (values KIND DESCRIPTION-OR-NIL GATED-P).
   Otherwise return (values NIL NIL NIL).

   Recognised KINDs:
     :prose          for `===prose==='
     :code-eval      for `===eval==='
     :scene          for `===scene==='
     :code-exercise  for `===exercise: <desc>==='
     :code-solution  for `===solution: <desc>==='         (GATED-P nil)
                     and `===solution-locked: <desc>==='   (GATED-P t)
     :expect         for `===expect===' / `===expect: <desc>==='

   GATED-P is T only for the solution-locked variant; NIL otherwise."
  (cond ((string= line "===prose===") (values :prose nil nil))
        ((string= line "===eval===") (values :code-eval nil nil))
        ((string= line "===scene===") (values :scene nil nil))
        (t
         (multiple-value-bind (m groups)
             (cl-ppcre:scan-to-strings +exercise-header-regex+ line)
           (when m
             (return-from parse-fence-header
               (values :code-exercise (aref groups 0) nil))))
         (multiple-value-bind (m groups)
             (cl-ppcre:scan-to-strings +solution-locked-header-regex+ line)
           (when m
             (return-from parse-fence-header
               (values :code-solution (aref groups 0) t))))
         (multiple-value-bind (m groups)
             (cl-ppcre:scan-to-strings +solution-header-regex+ line)
           (when m
             (return-from parse-fence-header
               (values :code-solution (aref groups 0) nil))))
         (multiple-value-bind (m groups)
             (cl-ppcre:scan-to-strings +expect-header-regex+ line)
           (when m
             (return-from parse-fence-header
               (values :expect (aref groups 0) nil))))
         (values nil nil nil))))
```

- [ ] **Step 3c: `parse-notebook-body` で gated を配線** — `lisp-read-file` name_pattern=`parse-notebook-body` で現在の実装を読む。`parse-fence-header` を呼ぶ箇所で3値目 `gated-p` を受け取り、cell 生成（`make-cell`）に `:gated gated-p` を渡す。solution セルを生成する箇所（および汎用の `make-cell` 呼び出し）に `:gated` を追加する。`take-matching-cell-id` による id 継承ロジックには `gated` を含めない（本文一致で id 維持）。

  実装メモ: `parse-fence-header` の戻り値を `(multiple-value-bind (kind desc gated) (parse-fence-header line) ...)` で受け、状態機械が「現在のセル」を確定して `make-cell` する箇所に `:gated (and gated t)` を渡す。solution 以外では `gated` は nil のまま。

- [ ] **Step 4: リロードして成功を確認** — `load-system` system=`recurya/game/notebook-parser` force=true → tests システムも force=true → `run-tests` 上記2テスト。Expected: PASS。加えて `run-tests` system=`recurya/tests/game/notebook-parser`（全体）でリグレッションなしを確認。

- [ ] **Step 5: コミット**

```bash
git add game/notebook-parser.lisp tests/game/notebook-parser.lisp
git commit -m "feat: parse ===solution-locked:=== into a gated code-solution cell"
```

---

## Task 3: シリアライザが gated solution を出力 + ラウンドトリップ

**Files:**
- Modify: `game/notebook-parser.lisp`（`render-cell` の solution 出力）
- Test: `tests/game/notebook-parser.lisp`

- [ ] **Step 1: 失敗するテストを書く**

```lisp
(deftest cells->body-md-writes-solution-locked
  (testing "a gated solution serializes with the -locked header"
    (let ((cells (list (make-cell :kind :code-solution :description "ans"
                                  :body "(define x 1)" :gated t))))
      (ok (string= (format nil "===solution-locked: ans===~%(define x 1)")
                   (cells->body-md cells))))))

(deftest solution-gated-round-trips
  (testing "parse -> serialize -> parse preserves gated for both variants"
    (let* ((body (format nil "===exercise: q===~%; ?~%~%===expect===~%1~%~%===solution-locked: a===~%(+ 1 0)~%~%===solution: b===~%(+ 2 0)"))
           (cells (parse-notebook-body body))
           (round (parse-notebook-body (cells->body-md cells)))
           (sol-locked (find :code-solution round :key #'cell-kind))
           (sol-plain (find-if (lambda (c) (and (eq :code-solution (cell-kind c))
                                                (not (cell-gated c))))
                               round)))
      (ok (eq t (cell-gated sol-locked)) "gated solution stays gated")
      (ok sol-plain "plain solution stays non-gated"))))
```

- [ ] **Step 2: 実行して失敗を確認** — `run-tests` 上記2テスト。Expected: FAIL（`render-cell` が常に `===solution:` を出力）。

- [ ] **Step 3: 実装** — `game/notebook-parser.lisp` の `render-cell`（stream 版, 行 354 付近）の `:code-solution` 分岐を gated 対応に。`lisp-patch-form` で `ecase` の solution 行を置換。

  現在:
```lisp
      (:code-solution (format stream "===solution: ~A===" desc))
```
  置換後:
```lisp
      (:code-solution
       (if (cell-gated cell)
           (format stream "===solution-locked: ~A===" desc)
           (format stream "===solution: ~A===" desc)))
```

- [ ] **Step 4: リロードして成功を確認** — `load-system force=true`（parser + tests）→ `run-tests` 上記2テスト + `recurya/tests/game/notebook-parser` 全体。Expected: PASS。

- [ ] **Step 5: コミット**

```bash
git add game/notebook-parser.lisp tests/game/notebook-parser.lisp
git commit -m "feat: serialize gated solutions as ===solution-locked:==="
```

---

## Task 4: JSONB round-trip で `gated` を保存

**Files:**
- Modify: `game/notebook-jsonb.lisp`（`cell->jsonb-form` に `"gated"`、`jsonb-hash->cell` で読取）
- Test: `tests/game/notebook.lisp`

- [ ] **Step 1: 失敗するテストを書く** — `tests/game/notebook.lisp` に追加。full JSON 往復（`json->string` → `parse-json` → `jsonb-hash->cell`）で boolean クセを検出。パッケージに `recurya/game/notebook-jsonb` と `recurya/utils/common` の利用を用意（フル修飾で呼ぶので import 不要）。

```lisp
(deftest gated-survives-jsonb-json-round-trip
  (testing "cell->jsonb-form + json->string + parse-json + jsonb-hash->cell keeps gated"
    (dolist (g (list t nil))
      (let* ((cell (make-cell :kind :code-solution :description "d"
                              :body "(x)" :gated g))
             (json (recurya/utils/common:json->string
                    (recurya/game/notebook-jsonb:cell->jsonb-form cell)))
             (parsed (recurya/utils/common:parse-json json))
             (back (recurya/game/notebook-jsonb:jsonb-hash->cell parsed)))
        (ok (eq (and g t) (cell-gated back))
            (format nil "gated ~A round-trips" g))))))
```

- [ ] **Step 2: 実行して失敗を確認** — `run-tests` test=`recurya/tests/game/notebook::gated-survives-jsonb-json-round-trip`。Expected: FAIL（`cell->jsonb-form` が `"gated"` を出さない → back の gated が常に nil）。

- [ ] **Step 3a: `cell->jsonb-form` に `"gated"` を追加** — `lisp-patch-form`。既存の `(setf (gethash ...) ...)` 群に `"gated"` を1行追加。

  現在の末尾付近（`"test-cases"` の setf の後）に:
```lisp
          (gethash "gated"       h) (and (cell-gated cell) t)
```
  （`setf` の並列代入内に追記。既存の setf フォーム内へ `lisp-patch-form` で `(gethash "test-cases"  h)` の代入行群の直前に `(gethash "gated" h) (and (cell-gated cell) t)` を挿入する。順序は任意。）

- [ ] **Step 3b: `jsonb-hash->cell` で `"gated"` を読取** — `lisp-patch-form`。`make-cell` 呼び出しに `:gated` を追加。JSON parser の boolean 表現に依存しないよう堅牢に coerce（`true`→`t`/`false`→`nil` を想定しつつ、真偽以外は「文字列 "false"/keyword :false は偽」に倒す）。

```lisp
     :gated (let ((g (gethash "gated" h)))
              (cond ((null g) nil)
                    ((eq g t) t)
                    ((equal g "false") nil)
                    ((eq g :false) nil)
                    (t (and g t))))
```

  （`make-cell` の引数に上記 `:gated ...` を追加する。`lisp-patch-form` で `:test-cases` 引数の直前/直後に挿入。）

- [ ] **Step 4: リロードして成功を確認** — `load-system` system=`recurya/game/notebook-jsonb` force=true（依存する notebook も必要なら先に）→ tests システム force=true → `run-tests` 上記テスト。Expected: PASS。もし FAIL（boolean 表現が想定外）なら、`repl-eval`（純関数・DB 非依存）で `(recurya/utils/common:parse-json "{\"gated\":true}")` の `"gated"` 値を確認し、Step 3b の coerce を合わせる。

- [ ] **Step 5: コミット**

```bash
git add game/notebook-jsonb.lisp tests/game/notebook.lisp
git commit -m "feat: round-trip cell.gated through the notebook cells JSONB"
```

---

## Task 5: JS の `cellsToBody`/state が `gated` を扱う（node）

**Files:**
- Modify: `resources/static/js/cell-editor.js`（`renderCellHeader`/`renderCell`/`serverCellToState`/`stateCellToServer`/`emptyCell`）
- Test: `resources/static/js/cell-editor.test.mjs`

- [ ] **Step 1: 失敗するテストを書く** — `cell-editor.test.mjs` 末尾（既存 `console.log(...)` 群の後）に追加。`serverCellToState`, `stateCellToServer`, `cellsToBody` は import 済み。

```js
// Gated solutions: `gated` is a boolean carried through state and encoded as
// the ===solution-locked:=== fence variant.
{
  // cellsToBody: gated vs plain solution header.
  assert.strictEqual(
    cellsToBody([{ 'cell-id': '', kind: 'code-solution', body: '(x)',
                   description: 'a', 'test-cases': [], gated: true }]),
    '===solution-locked: a===\n(x)');
  assert.strictEqual(
    cellsToBody([{ 'cell-id': '', kind: 'code-solution', body: '(x)',
                   description: 'a', 'test-cases': [], gated: false }]),
    '===solution: a===\n(x)');

  // serverCellToState / stateCellToServer carry gated (boolean, missing => false).
  const st = serverCellToState({ 'cell-id': '', kind: 'code-solution', body: '(x)',
                                 description: 'a', 'test-cases': [], gated: true });
  assert.strictEqual(st.gated, true);
  assert.strictEqual(stateCellToServer(st).gated, true);
  const st2 = serverCellToState({ 'cell-id': '', kind: 'code-solution', body: '(x)',
                                  description: 'a', 'test-cases': [] });
  assert.strictEqual(st2.gated, false, 'missing gated => false');
}
console.log('ok: gated solutions encode ===solution-locked:=== and round-trip through state');
```

- [ ] **Step 2: 実行して失敗を確認** — `node resources/static/js/cell-editor.test.mjs`。Expected: FAIL（`gated` 未対応で header が `===solution:` のまま／`st.gated` undefined）。

- [ ] **Step 3a: `renderCellHeader` を cell 受け取りに変更** — `renderCellHeader(kind, description)` を `renderCellHeader(cell)` に変更し、内部で `cell.kind`/`cell.description`/`cell.gated` を参照。`code-solution` で gated 分岐。

```js
function renderCellHeader(cell) {
  const kind = cell.kind;
  const description = cell.description ?? '';
  switch (kind) {
    case 'prose':
      return '===prose===';
    case 'code-eval':
      return '===eval===';
    case 'scene':
      return '===scene===';
    case 'code-exercise':
      return `===exercise: ${description}===`;
    case 'code-solution':
      return cell.gated
        ? `===solution-locked: ${description}===`
        : `===solution: ${description}===`;
    default:
      throw new Error(`cellsToBody: unknown cell kind "${kind}"`);
  }
}
```

- [ ] **Step 3b: `renderCell` の呼び出しを更新** — `const header = renderCellHeader(cell.kind, description);` を `const header = renderCellHeader(cell);` に変更。

- [ ] **Step 3c: `serverCellToState` / `stateCellToServer` / `emptyCell` に gated** —
  - `serverCellToState` の返却オブジェクトに `gated: serverCell.gated === true,` を追加。
  - `stateCellToServer` の返却オブジェクトに `gated: stateCell.gated === true,` を追加。
  - `emptyCell` の返却に `gated: false,` を追加。

- [ ] **Step 4: 実行して成功を確認** — `node resources/static/js/cell-editor.test.mjs`。Expected: 全 `ok`（新規行含む）。`node --check resources/static/js/cell-editor.js` → syntax OK。

- [ ] **Step 5: コミット**

```bash
git add resources/static/js/cell-editor.js resources/static/js/cell-editor.test.mjs
git commit -m "feat: JS cellsToBody/state carry solution gated flag"
```

---

## Task 6: 編集UIに「正解後のみ表示」チェックボックス

**Files:**
- Modify: `resources/static/js/cell-editor.js`（`buildCellItemDom` の solution 用 UI）

- [ ] **Step 1: 実装（DOM・node テスト不可のためロジックを注意深く）** — `lisp-read-file` 相当で JS の `buildCellItemDom` を Read し、`code-exercise`/`code-solution` のときタイトル入力を出している箇所を確認。solution のとき（`cell.kind === 'code-solution'`）にチェックボックスを追加する。純関数のヘルパー `buildGatedCheckbox(cell)` を作る:

```js
/**
 * Build the "reveal only after passing" checkbox for a code-solution cell,
 * bound to cell.gated. Only shown for code-solution cells.
 *
 * @param {object} cell
 * @returns {HTMLLabelElement}
 */
function buildGatedCheckbox(cell) {
  const label = document.createElement('label');
  label.className = 'cell-editor-field cell-editor-gated';
  const input = document.createElement('input');
  input.type = 'checkbox';
  input.checked = cell.gated === true;
  input.addEventListener('change', () => {
    cell.gated = input.checked;
  });
  label.appendChild(input);
  label.appendChild(
    document.createTextNode(' 正解後のみ表示（直前の演習に正解するまで解答を隠す）')
  );
  return label;
}
```

  `buildCellItemDom` で、タイトル入力を追加している条件分岐に隣接して、`if (cell.kind === 'code-solution') { item.appendChild(buildGatedCheckbox(cell)); }` を追加（タイトル入力の直後。DOM 構造は既存のセル項目コンテナに追記）。**再描画（renderAll）で状態が保たれること**は既存の view 吸い上げ機構と同様に、`cell.gated` が state に直接束縛されているため保証される（CM view とは独立）。

- [ ] **Step 2: 回帰確認** — `node resources/static/js/cell-editor.test.mjs`（全 `ok`、トップレベル DOM 非依存が保たれること）+ `node --check resources/static/js/cell-editor.js`。Expected: pass / syntax OK。

- [ ] **Step 3: 手動確認メモ** — ブラウザ実機確認は controller 側。実装者は「code-solution セル選択時のみチェックボックスが出る」「チェックで `cell.gated` が true になる」ことをコード上で保証したことを報告。

- [ ] **Step 4: コミット**

```bash
git add resources/static/js/cell-editor.js
git commit -m "feat: cell editor checkbox to gate a solution behind passing"
```

---

## Task 7: 読者ページで solution を `<details>`／ロック描画

**Files:**
- Modify: `web/ui/notebook.lisp`（`*cells*` 動的変数、`render`、`preceding-exercise-passed-p`、`render-solution-cell`、`render-cell` の `:code-solution`、`<details>`/ロック用 CSS）
- Test: `tests/web/notebook-routes.lisp`

- [ ] **Step 1: 失敗するテストを書く** — `tests/web/notebook-routes.lisp` に追加。既存の `mk-user`/`with-mock-session`/`create-notebook!`/`notebook-edit-handler` ではなく、**読者ページ**（`public-notebook-by-handle-handler`）を使う。solution 本文が「未合格ではHTMLに出ない・合格では出る・非gatedは常時出る」を検証。

```lisp
(deftest solution-gated-hidden-until-passed
  (testing "a gated solution body is absent from the reader page until the
preceding exercise is passed; a non-gated solution is always shown"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (handle (users-handle dao))
             (body (format nil "===exercise: q===~%; ?~%~%===expect===~%1~%~%===solution-locked: ans===~%(SECRET-ANSWER)~%~%===solution: open===~%(OPEN-ANSWER)"))
             (nb (create-notebook! :title "N" :slug "n" :body-md body
                                   :cells nil :status "published" :visibility "public"
                                   :published-at (local-time:now) :author dao))
             (slug (recurya/db/notebooks:notebook-slug nb)))
        (declare (ignore nb))
        ;; Anonymous viewer: gated solution body hidden, non-gated shown.
        (with-mock-session (make-session)
          (let ((page (first (response-body
                              (public-notebook-by-handle-handler
                               (list (cons :captures (list handle slug))))))))
            (ng (search "SECRET-ANSWER" page)
                "gated solution body is NOT in the HTML when not passed")
            (ok (search "OPEN-ANSWER" page)
                "non-gated solution body IS shown")))))))
```

  注: `create-notebook!` の `:slug`/`notebook-slug` と、`public-notebook-by-handle-handler` の captures 形は既存テスト（`public-course-...` や `public-notebook-...`）を参照して合わせること。合格状態の検証（合格後に本文が出る）は Task 8 の実行経路と合わせて追加してもよいが、本タスクでは「未合格で隠れる／非gatedは出る」を最低限とする。

- [ ] **Step 2: 実行して失敗を確認** — `run-tests` test=`recurya/tests/web/notebook-routes::solution-gated-hidden-until-passed`。Expected: FAIL（現状 solution は本文を一切出さないため `OPEN-ANSWER` も出ず assert 失敗、かつ将来の gated 分岐が無い）。

- [ ] **Step 3a: `*cells*` 動的変数を追加** — `web/ui/notebook.lisp` の `*passed-cells*` 等の defparameter 群の近くに追加。

```lisp
(defparameter *cells* ()
  "All cells of the notebook currently being rendered, so a solution cell can
look back for its preceding exercise. Bound in RENDER.")
```

- [ ] **Step 3b: `render` で `*cells*` を束縛** — `lisp-read-file` name_pattern=`^render$` で `render` を読み、`*passed-cells*`/`*saved-codes*` を `let`/`progv` で束縛している箇所に `(*cells* (notebook-cells notebook))` を追加（同じ束縛フォーム内）。

- [ ] **Step 3c: ヘルパー2つを追加** — `render-cell` の直前に挿入。

```lisp
(defun preceding-exercise-passed-p (index)
  "True when the nearest :code-exercise cell before INDEX in *cells* has been
passed (its cell-id is in *passed-cells*). NIL when there is no preceding
exercise."
  (loop for i from (1- index) downto 0
        for c = (nth i *cells*)
        when (eq (cell-kind c) :code-exercise)
          do (return (and (member (%cell-id->string (cell-id c)) *passed-cells*
                                   :test #'string=)
                          t))
        finally (return nil)))

(defun render-solution-cell (cell index)
  "Render a :code-solution cell. A non-gated solution is always shown in a
collapsible <details>. A gated solution shows its body only when its preceding
exercise is passed; otherwise only a locked placeholder (the body is never
emitted). Always emits the empty hidden codes[] placeholder for index
alignment. The container id cell-<index>-solution is the HTMX OOB target."
  (let* ((unlocked (or (not (cell-gated cell))
                       (preceding-exercise-passed-p index)))
         (container-id (format nil "cell-~D-solution" index)))
    (with-html
      (:div :id container-id :class "cell cell--solution"
        (if unlocked
            (:details :class "solution-details"
              (:summary "解答を見る")
              (:pre :class "solution-body" (or (cell-body cell) "")))
            (:div :class "solution-locked"
              "🔒 直前の演習に正解すると解答が表示されます")))
      (:input :type "hidden" :class "notebook-code" :name "codes[]" :value ""))))
```

- [ ] **Step 3d: `render-cell` の `:code-solution` を差し替え** — `lisp-patch-form` で `render-cell` の `ecase` の `:code-solution` 節を `(:code-solution (render-solution-cell cell index))` に置換。

- [ ] **Step 3e: CSS を追加** — `*styles*`（defparameter）末尾付近に solution 用スタイルを追記（`lisp-patch-form` で `*styles*` 文字列内に連結）。

```css
.cell--solution { }
.solution-details { background:#111827; border:1px solid #334155;
                    border-radius:8px; padding:0.5rem 0.75rem; }
.solution-details > summary { cursor:pointer; color:#38bdf8; font-weight:600;
                              font-size:0.9rem; }
.solution-body { margin:0.5rem 0 0 0; color:#e2e8f0; font-family:'SF Mono',monospace;
                 font-size:0.85rem; white-space:pre-wrap; }
.solution-locked { color:#64748b; font-size:0.85rem; padding:0.5rem 0.75rem;
                   border:1px dashed #334155; border-radius:8px; }
```

- [ ] **Step 4: リロードして成功を確認** — `load-system` system=`recurya/web/ui/notebook` force=true → tests システム force=true → `run-tests` 上記テスト + `recurya/tests/web/notebook-routes` 全体。Expected: PASS（`SECRET-ANSWER` 不在・`OPEN-ANSWER` 在）。

- [ ] **Step 5: コミット**

```bash
git add web/ui/notebook.lisp tests/web/notebook-routes.lisp
git commit -m "feat: render solution cells as collapsible details with gating"
```

---

## Task 8: exercise 合格時に gated solution を HTMX で即時解放

**Files:**
- Modify: `web/ui/notebook.lisp`（`render-solution-oob-reveals`）
- Modify: `web/routes.lisp`（`%run-public-cell` の `:pass` 時に連結）
- Test: `tests/web/notebook-routes.lisp`

- [ ] **Step 1: 失敗するテストを書く** — exercise の Run が `:pass` の時、直後の gated solution の OOB reveal（`hx-swap-oob` + 本文）が Run レスポンスに含まれること。`public-notebook-cell-run-by-handle-handler` を使う（既存テスト `public-notebook-cell-run-...` を参照して呼び出し形を合わせる）。

```lisp
(deftest exercise-pass-oob-reveals-gated-solution
  (testing "passing an exercise reveals the following gated solution via OOB swap"
    (with-test-db
      (let* ((user (mk-user))
             (dao (get-user-by-id (getf user :id)))
             (handle (users-handle dao))
             ;; exercise at index 0 (passes when code returns 3), gated solution at index 1.
             (body (format nil "===exercise: q===~%; fill~%~%===expect===~%3~%~%===solution-locked: ans===~%(SECRET-ANSWER)"))
             (nb (create-notebook! :title "N" :slug "n" :body-md body
                                   :cells nil :status "published" :visibility "public"
                                   :published-at (local-time:now) :author dao))
             (slug (recurya/db/notebooks:notebook-slug nb)))
        (declare (ignore nb))
        (with-mock-session (make-session :user user)
          ;; Submit correct code so the single test-case (expected 3) passes.
          ;; codes[] is positional: exercise is cell 0.
          (let ((res (public-notebook-cell-run-by-handle-handler
                      (list (cons :captures (list handle slug "0"))
                            (cons "codes[]" "3")))))
            (let ((frag (first (response-body res))))
              (ok (= 200 (response-status res)))
              (ok (search "hx-swap-oob" frag) "response carries an OOB swap")
              (ok (search "cell-1-solution" frag) "targets the gated solution container")
              (ok (search "SECRET-ANSWER" frag) "reveals the solution body on pass"))))))))
```

  注: `public-notebook-cell-run-by-handle-handler` の captures とパラメータ（`:index` の渡し方、`codes[]` の複数値）を既存の cell-run テストに厳密に合わせること。exercise が `:pass` になる `expect`/`codes[]` の組は、`3` を返すコードにする（`===expect===\n3` の単一行期待値 + `codes[]="3"`）。

- [ ] **Step 2: 実行して失敗を確認** — `run-tests` 上記テスト。Expected: FAIL（現状 Run レスポンスは結果パネルのみで OOB 無し）。

- [ ] **Step 3a: `render-solution-oob-reveals` を追加** — `web/ui/notebook.lisp` に。exercise index を渡すと、その exercise に紐づく gated solution 群（index+1 から次の exercise 手前までの `:code-solution` かつ `gated`）を、解放後の `<details>` を `hx-swap-oob="true"` の同 id コンテナで包んで返す（無ければ空文字列）。

```lisp
(defun render-solution-oob-reveals (cells exercise-index)
  "Return HTML (string) of out-of-band <div id=\"cell-<M>-solution\"
hx-swap-oob=\"true\"> reveals for every gated :code-solution cell that belongs
to the exercise at EXERCISE-INDEX (i.e. appears after it, before the next
exercise). Empty string when there are none. Intended to be appended to a Run
response after a :pass so the solution unlocks instantly."
  (with-html-string
    (loop for i from (1+ exercise-index) below (length cells)
          for c = (nth i cells)
          until (eq (cell-kind c) :code-exercise)
          when (and (eq (cell-kind c) :code-solution) (cell-gated c))
            do (let ((cid (format nil "cell-~D-solution" i)))
                 (:div :id cid :class "cell cell--solution" :hx-swap-oob "true"
                   (:details :class "solution-details"
                     (:summary "解答を見る")
                     (:pre :class "solution-body" (or (cell-body c) "")))
                   (:input :type "hidden" :class "notebook-code"
                           :name "codes[]" :value ""))))))
```

  注: 解放後コンテナは Task 7 の `render-solution-cell` の解放時 DOM と**同一構造**にする（id・class・details・pre・hidden input）。DRY のため、可能なら「解放後の details 部分」を共通ヘルパー化してもよいが、必須ではない。

- [ ] **Step 3b: `%run-public-cell` で `:pass` 時に連結** — `web/routes.lisp` の `%run-public-cell` の成功分岐（`(t ...)` の `run-cell` → `render-cell-result` → `html-response body`）を修正。実行したセルが `:code-exercise` で結果 status が `:pass` の時、`render-solution-oob-reveals` の出力を `body` に連結してから `html-response` する。

```lisp
                    (let* ((nb-uuid (princ-to-string (notebook-id nb-row)))
                           (result (run-cell notebook index codes-list))
                           (base (recurya/web/ui/notebook:render-cell-result result))
                           (reveals
                            (if (and (eq (cell-kind (nth index cells)) :code-exercise)
                                     (eq (notebook-cell-result-status result) :pass))
                                (recurya/web/ui/notebook:render-solution-oob-reveals
                                 cells index)
                                ""))
                           (body (concatenate 'string base reveals)))
                      (%maybe-persist-notebook-cell-run uid nb-uuid
                                                        (nth index cells)
                                                        result
                                                        (nth index codes-list))
                      (html-response body)))
```

  注: `render-solution-oob-reveals` を `recurya/web/ui/notebook` の `:export` に追加すること。`notebook-cell-result-status` は `recurya/game/notebook` から利用可能（`%run-public-cell` は既に result を扱う）。

- [ ] **Step 4: リロードして成功を確認** — `load-system` system=`recurya/web/ui/notebook` force=true → `recurya/web/routes` force=true → tests force=true → `run-tests` 上記テスト + `recurya/tests/web/notebook-routes` 全体。Expected: PASS。

- [ ] **Step 5: コミット**

```bash
git add web/ui/notebook.lisp web/routes.lisp tests/web/notebook-routes.lisp
git commit -m "feat: reveal gated solution via HTMX OOB swap on exercise pass"
```

---

## Task 9: 全体回帰 + 手動 E2E

**Files:** なし（検証のみ）

- [ ] **Step 1: 全 Lisp テスト** — `run-tests` system=`recurya/tests`。Expected: 全 PASS（既存 + 新規）。
- [ ] **Step 2: 全 node テスト** — `node resources/static/js/cell-editor.test.mjs`。Expected: 全 `ok`。
- [ ] **Step 3: 手動 E2E（controller/ユーザー）** — ブラウザで:
  1. 編集画面で solution セルに「正解後のみ表示」チェック→保存→再編集でチェック状態が保たれる（ラウンドトリップ）。
  2. 読者ページ（未ログイン/直前 exercise 未合格）で gated solution が「🔒…」表示・本文が DOM に無い（devtools 確認）。
  3. 直前 exercise を解いて Run→**その場で** solution が `<details>` に展開（HTMX OOB）。
  4. 非 gated solution は常時 `<details>` 表示。
  5. ログインユーザーで合格後リロード→解放済みのまま。
- [ ] **Step 4: 最終コミット（あれば）** — 手動修正が出た場合のみ。

---

## Self-Review 結果

- **Spec coverage**: §4→Task1, §5.1→Task2, §5.2→Task3, §6.1→Task4, §6.2→Task5, §6.3→Task6, §7→Task7, §8→Task8, §10→各 Task のテスト + Task9。全カバー。
- **後方互換**（spec §11）: 既存 `===solution:===` は Task2/3 で `gated=nil`＝常時折りたたみ。Task7 で非 gated は常時 `<details>`。移行不要。
- **型整合**: `gated` は Lisp boolean（`cell-gated`）、JSONB `"gated"`（t/nil→true/false、Task4 で堅牢 coerce）、JS `gated`（boolean, `=== true`）。フェンス語は全経路 `===solution-locked:===`（Lisp render-cell / JS renderCellHeader）で一致。コンテナ id は `cell-<index>-solution`（Task7 render-solution-cell と Task8 render-solution-oob-reveals で同一）。
- **未確定の実装ディテール**: (a) `parse-notebook-body` 内の `make-cell` 呼び出し位置（Task2 Step3c、実装時に現物確認）、(b) `render`/`%run-public-cell` の束縛・分岐の現物（Task7/8、`lisp-read-file` で確認）、(c) `public-notebook-cell-run-by-handle-handler` の captures/param 形（Task8、既存 cell-run テスト参照）。いずれもテストで担保。
