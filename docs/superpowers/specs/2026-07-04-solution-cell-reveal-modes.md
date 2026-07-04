# solution セルの表示モード（gated 解答）— 設計

- 日付: 2026-07-04
- 対象: ノートブックの `code-solution`（模範解答）セルの読者ページ描画と、著者による表示モード選択
- ステータス: 承認済み（レビュー通過、実装計画へ）

## 1. 背景・目的

`code-solution` セル（フェンス `===solution: <desc>===`、exercise の模範解答）は、モデル・パーサー・保存形式・編集フォームには存在するが、**読者ページの描画が未実装のスタブ**である。現状 `web/ui/notebook.lisp` の `render-cell` は `:code-solution` を「空の hidden input のみ」に描画し（`codes[]` のインデックス整列用プレースホルダ）、本文・説明を一切表示しない。`%run-public-cell` も solution を実行禁止にしている。結果、著者が solution セルを書いても読者には何も見えず、明かす手段もない。

本設計は solution セルを**実際に見せられる**ようにし、かつ **2つの表示モードを著者がセル単位で選べる**ようにする:

1. **常時折りたたみ**（デフォルト）: 読者が自分で `<details>` を展開して解答を見る。
2. **正解後のみ**: 直前の exercise に合格するまで解答をロック（本文を HTML に出さない）。合格した瞬間に HTMX で即時解放。

## 2. 対象範囲・非目標

**対象（MVP）**
- `cell` に `gated`（boolean）フィールドを追加し、フェンス形式・JSONB・JS・編集UI・描画・実行ハンドラに配線。
- 読者ページで solution を `<details>` 折りたたみとして描画（常時／正解後の2モード）。
- 「正解後のみ」の即時解放（HTMX out-of-band swap）。

**非目標（今回やらない）**
- solution ↔ exercise の明示的 ID 紐付け（「直前の exercise セル」で固定）。
- 複数 exercise へのゲート、全 exercise 合格でのゲート。
- solution セルの実行（従来通り実行不可）。
- リセット時の再ロック（一度合格すればログインユーザーはリロードで解放済みのまま）。

## 3. 用語・確定した挙動

- **モードの粒度**: solution セル単位。デフォルトは「常時折りたたみ」（`gated=nil`）。
- **「正解」の定義**: gated solution の**直前にある exercise セル**（セル列を後方に走査して最初に見つかる `:code-exercise`）に合格＝その exercise の `cell-id` が合格集合に含まれること。
- **ロック時のセキュリティ**: 未解放の gated solution は**本文を HTML に一切出力しない**（devtools/inspect で覗けない）。ロック表示（誘導文）のみ。
- **匿名ユーザー**: 合格が永続化されないため、描画時は常にロック。ただし、そのセッションで exercise に合格すれば HTMX OOB で即時解放される（本文はその瞬間に初めて配信）。リロードで再ロック。
- **ログインユーザー**: 合格は既存機構（`mark-cell-passed`）で永続化。次回描画時は解放済み。合格した瞬間も HTMX OOB で即時解放。
- **`codes[]` 整列**: solution セルは解放/ロックに関わらず、従来通り空の hidden `.notebook-code`（`codes[]=""`）を出力してセル・インデックス整列を維持する（解答コードを実行環境へ注入しない）。

## 4. データモデル

### 4.1 `cell` 構造体（`game/notebook.lisp`）
`defstruct cell` に `gated-p`（boolean, デフォルト `nil`）を追加。`:code-solution` でのみ意味を持つ（他 kind では常に `nil`）。アクセサ `cell-gated-p` を export（boolean は `-p` 接尾辞の規約）。`make-cell` 引数は `:gated-p`。

> **命名の層別**: Lisp は `gated-p`/`cell-gated-p`/`:gated-p`、JSON キーは `"gated"`、JS フィールドは `gated`（各層の慣習に従う）。以降 §5–§7 の Lisp コード中の `cell-gated`/`:gated` は `cell-gated-p`/`:gated-p` を指す。

### 4.2 フェンス形式（後方互換）
| 記法 | kind | gated |
|------|------|-------|
| `===solution: <desc>===` | `:code-solution` | `nil`（常時折りたたみ） |
| `===solution-locked: <desc>===` | `:code-solution` | `t`（正解後のみ） |

既存の全 `===solution:===` は `gated=nil`＝常時折りたたみとして動作。データ移行不要。

## 5. パーサー／シリアライザ（Lisp, `game/notebook-parser.lisp`）

### 5.1 `parse-fence-header`
- `+solution-locked-header-regex+`（`^===solution-locked: (.+)===$`）を追加。
- 戻り値を `(values KIND DESCRIPTION GATED-P)` の3値に拡張。`===solution:===` は `gated-p=nil`、`===solution-locked:===` は `gated-p=t`。他 kind は `gated-p=nil`。
- 既存呼び出し（`parse-notebook-body`）は3値目を受け取り、solution セル生成時に `:gated` へ渡す。

### 5.2 `render-cell` / `cells->body-md`
- `:code-solution` の描画時、`(cell-gated cell)` が真なら `===solution-locked: <desc>===`、偽なら従来通り `===solution: <desc>===` を出力。
- ラウンドトリップ（`cells->body-md` → `parse-notebook-body`）で `gated` が保存されることを保証。

### 5.3 `take-matching-cell-id`（cell-id 安定化）
既存の (kind body description) マッチングに影響なし（`gated` はマッチング条件に含めない。編集で常時↔正解後を切り替えても本文が同じなら cell-id は維持される）。

## 6. JSONB + JS パイプライン + 編集UI

### 6.1 JSONB（`game/notebook-jsonb.lisp`）
- `cell->jsonb-form`: `"gated"` キー（boolean）を追加。
- `jsonb-hash->cell`: `"gated"` を読み、`(and (gethash "gated" h) t)` 等で boolean 化して `:gated` に。

### 6.2 JS（`resources/static/js/cell-editor.js`）
- `serverCellToState`/`stateCellToServer`: `gated`（→内部 `gated`）を授受。サーバー形状キーは `gated`（ハイフンなし）。
- **boolean の授受**: `gated` は真偽値。`cell->jsonb-form` は `t`→`true` / `nil`→`false` を出力（boolean では `nil→false` は正しい。`test-cases` の空配列問題とは別）。JS は `serverCell.gated === true`（または `Boolean(...)`）で受け、`stateCellToServer` は真偽値を返す。欠落時は `false` 扱い。
- `renderCellHeader`/`cellsToBody`: `code-solution` かつ `gated` の時 `===solution-locked: <desc>===` を出力。
- 送信時にサーバー形状へ `gated` を含める。

### 6.3 編集UI（`cell-editor.js`）
- `code-solution` セルにチェックボックス **「正解後のみ表示（直前の演習に正解するまで解答を隠す）」** を追加（`buildTitleInput` と同じ位置に、solution のときだけ表示）。内部 state の `gated` にバインド。

### 6.4 パリティ
- Lisp `cells->body-md` と JS `cellsToBody` の**フェンス一致パリティテスト**に gated ケースを追加（`===solution-locked:===` が両者一致）。

## 7. 描画（読者ページ, `web/ui/notebook.lisp`）

### 7.1 `render-cell` の `:code-solution`
`render` は `*passed-cells*`（合格した cell-id 文字列のリスト）を動的束縛済み。**同様に `render` で動的変数 `*cells*`（現在描画中のノートブックの全セル列）を新設・束縛する**（既存の `*passed-cells*`/`*saved-codes*` と同じパターン）。`render-solution-cell` はこれを使って直前 exercise を後方走査する。`render-cell` のシグネチャ（`cell index nb-id`）は変更しない。

判定:
1. `解放? =` `(or (not (cell-gated cell)) (preceding-exercise-passed-p cells index))`
   - `preceding-exercise-passed-p`: `cells` を index-1 から後方走査し最初の `:code-exercise` を見つけ、その `cell-id` が `*passed-cells*` に含まれるか。exercise が無ければ（安全側で）ロック扱い。
2. **解放時**: 安定 id `cell-<index>-solution` のコンテナ内に `<details><summary>解答を見る</summary>…本文…</details>` を描画。本文は `pre`/コードブロック表示（wardlisp 想定、ハイライトは任意）。
3. **未解放時**: 同じ安定 id コンテナ内に**ロック表示のみ**（例: 「🔒 直前の演習に正解すると解答が表示されます」）。**本文は出力しない。**
4. いずれの場合も、従来の空 hidden `.notebook-code`（`codes[]=""`）を出力（整列維持）。

> コンテナ id `cell-<index>-solution` は HTMX OOB の差し替え先。

### 7.2 ヘルパー
- `render-solution-cell (cell index)` を新設し、上記のロック/解放分岐を担う。`render-cell` の `:code-solution` 分岐から呼ぶ。`*cells*` を参照。
- `preceding-exercise-passed-p (cells index)` を新設（`cells` は `*cells*` を渡す）。

## 8. HTMX 即時解放（実行ハンドラ, `web/routes.lisp` + `web/ui/notebook.lisp`）

### 8.1 フロー
1. 学習者が exercise（index N）の Run を押す → `%run-public-cell` が採点し `:pass`/`:fail`/`:error` を返す。
2. `:pass` の時、その exercise N に紐づく gated solution 群（下記 8.2）を探し、各々を**解放後の `<details>`** として描画し、`<div id="cell-<M>-solution" hx-swap-oob="true">…</div>` で包んで Run レスポンス本文に追記。
3. HTMX が結果パネル（`#cell-N-result`）と同時に、OOB 指定の各 `#cell-<M>-solution` を差し替え → **合格した瞬間に解放**。

### 8.2 「N に紐づく gated solution」の判定
- セル列を index N+1 から走査し、次の `:code-exercise` が現れる前までの `:code-solution` セルのうち `gated=t` のものが対象（それらの「直前 exercise」は N）。
- 対象が無ければ OOB 追記なし（レスポンスは従来通り）。

### 8.3 実装分担
- `web/ui/notebook.lisp` に `render-solution-oob-reveals (notebook exercise-index)` を新設: `:pass` を前提に、対象 gated solution 群の OOB HTML 文字列（無ければ空文字列）を返す。
- `%run-public-cell`: `result` が `:pass` の時、上記を呼び結果本文に連結して返す。`:fail`/`:error` の時は連結しない。
- 匿名・ログイン問わず同じ経路で解放（サーバーが「今まさに合格した」ことを知っているため本文を配信してよい）。

### 8.4 セキュリティ
- 未合格では本文が DOM に無く、Run エンドポイントは**実際に test-cases を評価して `:pass` の時のみ**解放するため、合格せずに解答を得る経路がない（正しいコードを提出＝解けている）。

## 9. エラー処理・エッジ

- gated solution の直前に exercise が存在しない場合: 安全側でロック（解放されない）。著者の構成ミスは編集時に気づける（読者ページで常にロック表示）。
- 常時折りたたみ（非 gated）solution: `*passed-cells*` に関係なく常に `<details>` 表示。OOB 対象外。
- exercise を一度合格後に編集して fail: OOB は fail 時に発火しないので即時再ロックはしない。ログインユーザーはリロードで解放済みのまま（合格記録は残る）。MVP では許容。

## 10. テスト方針

**パーサー（`tests/game/notebook-parser`）**
- `===solution-locked: x===` → `:code-solution` かつ `gated=t`。
- `===solution: x===` → `gated=nil`。
- ラウンドトリップ: gated/非 gated 混在 cells → `cells->body-md` → `parse-notebook-body` で `gated` 保存。

**JSONB（`tests/game/notebook-jsonb` 等）**
- `cell->jsonb-form`/`jsonb-hash->cell` round-trip で `gated` 保存。

**JS（`cell-editor.test.mjs`, node）**
- `serverCellToState`/`stateCellToServer` の `gated` 授受。
- `cellsToBody` が gated solution で `===solution-locked:===`、非 gated で `===solution:===`。
- Lisp `cells->body-md` とのパリティに gated ケース追加。

**描画（`tests/web/notebook-routes` 等）**
- gated + 直前 exercise 未合格（`*passed-cells*` 空）→ 本文が HTML に**含まれない**・ロック表示あり。
- gated + 直前 exercise 合格 → `<details>` と本文が含まれる。
- 非 gated → 常時 `<details>` と本文。

**実行（`tests/web/notebook-routes` 等）**
- exercise `:pass` 時、直後の gated solution の OOB reveal（`hx-swap-oob` と本文）が Run レスポンスに含まれる。
- `:fail` 時は含まれない。
- 匿名でも `:pass` 時は含まれる。

## 11. 後方互換・移行

- 既存 `===solution:===` は `gated=nil`＝常時折りたたみ。既存ノートブックはそのまま新描画（従来の「非表示」→「常時折りたたみ表示」に改善）。
- DB マイグレーション不要（`gated` は cells JSONB 内の任意キー。欠落時は `nil` 扱い）。

## 12. 影響ファイル一覧

- `game/notebook.lisp`: `cell` に `gated` + アクセサ export。
- `game/notebook-parser.lisp`: solution-locked 正規表現、`parse-fence-header` 3値化、`parse-notebook-body` 配線、`render-cell`/`cells->body-md` の gated 出力。
- `game/notebook-jsonb.lisp`: `"gated"` キー round-trip。
- `resources/static/js/cell-editor.js`: state 授受、`cellsToBody`/`renderCellHeader`、編集UIチェックボックス。
- `resources/static/js/cell-editor.test.mjs`: gated パリティ・state テスト。
- `web/ui/notebook.lisp`: `render-solution-cell`、`preceding-exercise-passed-p`、`render-solution-oob-reveals`、`render-cell` 差し替え。
- `web/routes.lisp`: `%run-public-cell` の `:pass` 時 OOB 連結。
- 各テストスイート（parser / jsonb / notebook-routes / node）。
