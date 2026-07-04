# exercise セルの複数行 Markdown 説明文 — 設計

- 日付: 2026-07-04
- 対象: `code-exercise` セルの「説明文（問題文）」を複数行 Markdown で記述できるようにする（編集エディタは Markdown シンタックスハイライト付き）
- ステータス: 承認済み（レビュー通過、実装計画へ）

## 1. 背景・目的

`code-exercise` セルの `description`（問題の説明文）は、現状フェンスヘッダ `===exercise: <desc>===` の**1行**に置かれる。読者ページでは既に `render-cell-prose-html`（3bmd Markdown → サニタイズ HTML）で Markdown レンダリングされ、`.cell__desc` の目立つブロックに表示される。しかし1行制約のため**複数行・段落の問題文が書けない**。加えて編集エディタでは単一行入力に「Title」ラベルが付いており、実際は description（問題説明）なのに誤解を招く。

本設計は exercise の説明文を**複数行 Markdown** で記述可能にし、編集エディタでは **CodeMirror 6 の Markdown ハイライト**付きで編集できるようにする。

## 2. 対象範囲・非目標

**対象（MVP）**
- exercise フェンス形式に `===code===` サブフェンスを導入し、説明文を複数行ブロックとして保持。
- パーサー（新形式パース + 旧形式後方互換）、シリアライザ（Lisp/JS、常に新形式）、編集UI（Markdown ハイライト付き説明文エディタ）、reader の微調整。

**非目標（今回やらない）**
- `code-solution` の description（読者ページに表示されない単なるラベル）は対象外。単一行「Title」のまま。
- reader ページの exercise 説明文レンダリング自体の刷新（既に Markdown 済み。CSS 微調整のみ）。
- 説明文中に `===code===`/`===expect===` 等のフェンス様行を含むケースの完全エスケープ（低リスク、既知の限界として許容）。

## 3. フェンス形式

### 3.1 新形式（シリアライザが常に出力）
```
===exercise===
<複数行 Markdown 説明文（0行以上）>
===code===
<コード穴埋め（0行以上）>
===expect[: <desc>]===
<期待値>
```
- `===exercise===`（bare ヘッダ）が exercise を開始。
- ヘッダ〜`===code===` の間 = **description**（複数行 Markdown、前後空白トリム）。
- `===code===`〜最初の `===expect===`（または次セル/EOF）= **body（コード穴埋め）**（前後空白トリム）。
- `===expect===` ブロック = test-cases（不変）。

### 3.2 旧形式（パーサーは受理・後方互換）
```
===exercise: <desc>===
<コード穴埋め>
===expect===
...
```
`===code===` を含まない。description = ヘッダの `<desc>`（単一行）、body = コード。既存ノートはそのまま動作。

## 4. パーサー（`game/notebook-parser.lisp`）

### 4.1 `parse-fence-header`
- `===code===` → 新センチネル種別 `:code-delim`（`===prose===` 等と同様に `string=` で判定。セルにはならず、状態機械が説明/コードを分割するために使う）。
- **bare `===exercise===` → `(values :code-exercise nil nil)`**（desc=nil）。現状の `+bare-exercise-header-regex+` による即エラーを廃し、bare exercise を「新形式のヘッダ」として受理する（説明の有無は close 時に判定）。
- `===exercise: <desc>===`（`+exercise-header-regex+`）→ 従来通り `:code-exercise` + desc。

### 4.2 状態機械（`parse-notebook-body`）
exercise 収集中の追加ルール:
- `===code===`（`:code-delim`）到達時:
  - `current-kind` が `:code-exercise` でない → エラー「===code=== is only valid inside an exercise」。
  - `current-desc` が非 nil（＝ヘッダに desc がある、または既にこの exercise で `===code===` を見た）→ エラー「unexpected ===code=== (the description is already set — either in the ===exercise: ...=== header or a previous ===code=== block)」。
  - それ以外（bare exercise 収集中、`current-desc` = nil）→ **これまでの `current-buffer` を説明文として `current-desc` にセット**（`buffer-string` でトリム。空なら ""）、`current-buffer` をリセットし以後コードを収集。
- exercise を閉じる（`close-exercise-body`、次の非 expect ヘッダ / EOF）時:
  - `current-desc` が **nil**（bare ヘッダかつ `===code===` 未出現）→ エラー「exercise requires a description or a ===code=== block」。当該 exercise は生成しない（drop。save は parse-errors で拒否される）。
  - `current-desc` が非 nil（ヘッダ desc、または `===code===` 後のブロック desc。空文字 "" 含む）→ `make-cell :kind :code-exercise :description current-desc :body (コード)`。

> **nil と "" の区別**: bare `===exercise===` はヘッダ由来 desc=nil で開始。`===code===` を見て初めて `current-desc` に文字列（空でも ""）がセットされる。よって close 時の `current-desc` が nil = 「bare かつ code ブロック無し」= エラー、非 nil = 正常、で判別できる。

### 4.3 バリデーションエラー一覧（変更点）
- 追加: 「===code=== outside an exercise」/「description in header + ===code=== block」/「bare exercise without description or ===code===」。
- 廃止/移動: `===exercise===`（bare）の即時「requires a description」→ close 時の判定に移動（bare + code ブロックありは正常、bare + code 無しはエラー）。

## 5. シリアライザ（Lisp `render-cell` + JS `cellsToBody`）— 常に新ブロック形式

### 5.1 Lisp（`game/notebook-parser.lisp` の `render-cell` stream 版）
`:code-exercise` の出力を:
```
===exercise===
<description>
===code===
<body>
```
（description 空なら空行）+ 各 test-case（`render-test-case`、不変）。他 kind（prose/eval/solution/scene）は不変。

### 5.2 JS（`resources/static/js/cell-editor.js`）
`cellsToBody`/`renderCell` の `code-exercise` を、上記 Lisp と**byte 一致**する新ブロック形式で出力（`renderCellHeader` は exercise 以外に使い続け、exercise は `renderCell` 側で特別扱い）。test-case 連結は不変。

### 5.3 ラウンドトリップ・移行
- 新形式 `cells->body-md` ⇄ `parse-notebook-body` で description（複数行）と body が保存される。
- 既存 exercise（旧形式）は読み込み時はそのまま、**再保存時に新形式へ移行**（body_md 文字列が変わるが意味は同一。[[cell-editor-merged-e2e-pending]] の body_md 正規化と同種）。

## 6. 編集UI（`resources/static/js/cell-editor.js`）

- exercise セルの単一行「Title」入力（`buildTitleInput`）を、**Markdown シンタックスハイライト付き CodeMirror 6 エディタ**「Description（Markdown）」に置換。`cell.description` にバインド。prose セルで実装済みの `markdownExtensions`（Markdown StreamParser + HighlightStyle：見出し/太字/斜体/コード/リンク/引用/リスト）を再利用。
- 結果、exercise セルは **CM6 エディタを2つ**持つ: 上＝説明文（markdown）、下＝コード穴埋め（scheme）。
- 内部状態に説明用 view（`cell.descView`）を追加し、既存の view ライフサイクルで code 用 view（`cell.view`）と共に管理:
  - `buildDescriptionEditor(editorState, cell)`: markdown CM6 view を生成し `cell.descView` に保持。
  - `syncAllViewsToState`: `cell.view`（→body）に加え `cell.descView`（→`cell.description`）も吸い上げ。
  - `destroyAllViews`: `cell.view` と `cell.descView` の両方を destroy。
  - `renderAll`（吸い上げ→destroy→再構築）が両 view を扱う。
- solution は現状の単一行「Title」入力のまま（スコープ外）。
- CM6 読込失敗時のフォールバックは既存の try/catch（従来 textarea へ）に従う。

## 7. reader（`web/ui/notebook.lisp`）

- exercise 説明文は既に `render-code-cell` 内で `render-cell-prose-html`（3bmd Markdown）レンダリング済み。複数行 Markdown も段落・箇条書きとして描画される。**ロジック変更なし**。
- `.cell__desc` の CSS `white-space: pre-wrap` → `normal` に変更（レンダリング済み HTML 段落向け。pre-wrap だとブロック間に余分な空白が出るため）。

## 8. データモデル

- `cell` 構造体は無変更（`description` は既に文字列。複数行文字列を保持できる）。JSONB 往復も無変更（`description` キーは既存）。
- 変わるのは**フェンスのシリアライズ/パース**のみ（description の格納場所がヘッダ行→ブロック）。

## 9. テスト方針

**パーサー（`tests/game/notebook-parser`）**
- 新形式 `===exercise===\n<md>\n===code===\n<code>` → desc（複数行）/body 正しく分割。
- 旧形式 `===exercise: d===\n<code>` → 後方互換（desc=d, body=code）。
- 空 desc（`===exercise===\n===code===\n<code>`）→ desc=""。
- エラー: bare exercise + `===code===` 無し / ヘッダ desc + `===code===` 併存 / exercise 外の `===code===`。
- ラウンドトリップ: 複数行 desc の exercise が parse→serialize→parse で保存。

**シリアライザ / パリティ**
- Lisp `cells->body-md` が新形式を出力（複数行 desc）。
- JS `cellsToBody` が同一 byte 列を出力（`cell-editor.test.mjs` のパリティに複数行 desc の exercise ケース追加）。

**reader（`tests/web/notebook-routes` 等）**
- 複数行 Markdown 説明文の exercise が読者ページで段落として描画される（`<p>` 複数 or リスト等）。

## 10. 影響ファイル一覧

- `game/notebook-parser.lisp`: `===code===` 認識、bare exercise 受理、状態機械の説明/コード分割、close 判定、`render-cell` の exercise 出力。
- `resources/static/js/cell-editor.js`: `cellsToBody`/`renderCell` の exercise 新形式、`buildDescriptionEditor`、view ライフサイクル（descView）、編集UI 差し替え。
- `resources/static/js/cell-editor.test.mjs`: 新形式パリティ・分割テスト。
- `web/ui/notebook.lisp`: `.cell__desc` の CSS 微調整。
- 各テストスイート（notebook-parser / node / notebook-routes）。

## 11. 後方互換・移行

- 既存 `===exercise: <desc>===`（旧形式）は読み込み時に動作。再保存で新形式へ移行（DB マイグレーション不要）。
- 空 exercise 説明文が新たに許容される（従来 bare exercise は即エラー）。
