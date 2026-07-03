# セル単位エディタ + CodeMirror 支援 — 設計

- 日付: 2026-07-04
- 対象: ノートブック編集フォーム（`/dashboard/notebooks/new`, `/dashboard/notebooks/:id/edit`）のオーサリング体験
- ステータス: 承認済み（レビュー通過、実装計画へ）

## 1. 背景・目的

現状、ノートブック本文は 1 つの大きな `<textarea>` に `===prose===` などのフェンスを書く方式（`web/ui/notebook-form.lisp`）。セルの境界が視覚的に分かりにくく、Markdown / wardlisp のシンタックス支援もない。

本設計は、編集フォームを **セル単位の個別エディタ** に刷新し、`prose` は Markdown、`eval`/`exercise`/`solution` は wardlisp(scheme近似) を **CodeMirror** の支援（ハイライト・括弧マッチ・インデント）付きで入力できるようにする。

## 2. 対象範囲・非目標

**対象（MVP）**
- 編集フォーム（新規/編集）のセル単位エディタ化と CodeMirror 支援
- セル操作: 追加（種別選択）/ 削除 / 上下移動

**非目標（今回やらない）**
- 公開ノートブックページ（`web/ui/notebook.lisp`）の exercise 穴埋め入力の CodeMirror 化
- ドラッグ&ドロップ並べ替え
- wardlisp シンボルのオートコンプリート
- サーバー側の保存形式・パーサーの変更

## 3. セル種別（既存 `cell` 構造）

`game/notebook.lisp` の `cell`（`:id :kind :body :description :test-cases`）と、`parse-fence-header` / `cells->body-md` のフェンス形式:

| kind | フェンス | 本文 | エディタモード |
|------|---------|------|--------------|
| `:prose` | `===prose===` | Markdown | markdown |
| `:code-eval` | `===eval===` | wardlisp | scheme |
| `:code-exercise` | `===exercise: <desc>===` | wardlisp(穴埋め) + test-cases | scheme + test-caseリスト |
| `:code-solution` | `===solution: <desc>===` | wardlisp | scheme |
| `:scene` | `===scene===` | シーン記述 | plain（既存保持のみ、新規種別セレクタには出さない） |

`:expect` はセルではなく、直前の `exercise` に付く test-case のセンチネル。test-case 本文は `input: <i>` / `output: <o>` の2行形式（input 非空時）、または単一行の期待値。

## 4. アプローチ（案A: フロントで組み立て、サーバー不変）

各 CodeMirror セルの内容を、**送信時に JS で既存のフェンス形式 `body` 文字列へ組み立て**、従来の `body` フィールドで POST する。サーバー（`notebook-create/update-handler`, `parse-notebook-body`, DB保存）は**一切変更しない**。既存のラウンドトリップ済みパーサー（`cells->body-md` ⇄ `parse-notebook-body`、テスト有り）をそのまま活かす。

不採用: セル配列JSONをPOSTしてサーバーで cells 構築する案（パーサー/ハンドラ改修が必要、リスク大）。

## 5. アーキテクチャ・コンポーネント

### 5.1 `web/ui/notebook-form.lisp`（変更）
- 既存の `cell` 群を **`data-cells` に JSON 埋め込み**（`render` に `:cells` を受け取る。編集時は DB の cells、新規時は空 or テンプレ）。
- 既存の `<textarea name="body">` は**残す**（フォールバック兼、送信キャリア）。JS 有効時は視覚的に隠し、送信直前に JS がフェンス body を書き込む。
- CodeMirror の CSS/JS を `<head>`/末尾で読み込む（`page-shell` の `head-extras`/`body-scripts` を利用）。
- ルートハンドラ `notebook-edit-handler` / `notebook-new-handler` は cells を plist 化して render に渡す（`notebook->plist` 相当を cells 込みに拡張）。

### 5.2 `resources/static/js/cell-editor.js`（新規）
- `data-cells` JSON を読み、各セルUIを DOM 構築:
  - 種別セレクタ（prose/eval/exercise/solution）
  - タイトル欄（exercise/solution のみ）
  - CodeMirror エディタ（種別に応じた mode）
  - exercise の test-cases（input/output ペアのリスト、追加/削除）
- ツールバー: 「セル追加（種別選択）」。各セル: 「↑ / ↓ / 削除」。
- **送信時（form submit）**: 全セルを走査し、`cells->body-md` と同一形式のフェンス文字列を生成 → hidden `body` にセットしてから送信。
- CodeMirror 読込失敗時は enhancement を中止し、従来の textarea をそのまま使わせる（下記 5.4）。

### 5.3 CodeMirror（CDN, CM5）
- `unpkg.com` から CodeMirror 5 の core + `mode/markdown` + `mode/scheme` を読み込む（htmx と同じ CDN 流儀）。
- wardlisp は scheme モードで近似ハイライト（S式・括弧・コメント）。

### 5.4 プログレッシブエンハンスメント
- サーバーは常に従来の `<textarea name="body">`（フェンス全文）をレンダリング。
- JS が正常動作した場合のみ、textarea を隠しセルエディタを表示。送信時に body を書き戻す。
- JS 無効 / CDN 読込失敗時は、従来の 1 テキストエリア編集がそのまま機能（機能低下なし）。

## 6. データフロー

```
編集: DB cells --(notebook-form:render)--> data-cells JSON + hidden <textarea body>(フェンス全文)
      --(cell-editor.js)--> セルエディタ生成
      --ユーザー編集-->
      --submit時: JS が全セル -> フェンス body 文字列 -> hidden textarea へ書き込み-->
      POST /dashboard/notebooks[/:id]
      --(既存 notebook-create/update-handler)--> parse-notebook-body -> cells -> DB(JSONB)
```

## 7. フェンス body 組み立て仕様（JS、`cells->body-md` 準拠）

- セル間は空行1つ（`\n\n`）で連結、末尾改行なし。
- 各セル:
  - prose: `===prose===\n<body>`
  - eval: `===eval===\n<body>`
  - exercise: `===exercise: <desc>===\n<body>` に続けて、各 test-case を
    - `===expect: <desc>===` または `===expect===`（test-case に desc がなければ）+ `\n<expect-body>`
    - expect-body: input 非空なら `input: <i>\noutput: <o>`、そうでなければ期待値単一行
  - solution: `===solution: <desc>===\n<body>`
  - scene: `===scene===\n<body>`
- この JS 出力は Lisp の `cells->body-md` と**同一のフェンス文字列**を生成しなければならない（ラウンドトリップ整合）。

## 8. エラー処理

- 空セル・タイトル欠落（exercise）などは、送信後にサーバーの `parse-notebook-body` が従来通り検証しエラー表示（既存フロー）。フロントでの事前バリデーションは MVP では最小（空 body 警告程度、任意）。
- CodeMirror 読込失敗はコンソール警告 + フォールバック（機能低下なし）。

## 9. テスト方針

- **サーバー**: 無変更。既存の `tests/game/notebook-parser`（ラウンドトリップ含む）で担保。
- **フロント（JS の body 組み立て）**: cells → フェンス body の生成が `cells->body-md` と一致することが要。JS 単体テストの基盤が無いため、当面は
  - 代表的な cells 群（prose/eval/exercise+expect/solution 混在）を JS で組み立て、既存 Lisp の `cells->body-md` の出力と突き合わせる検証（手動 or 軽量スクリプト）を実装計画で用意する。
- **手動E2E**: 新規作成→編集→再表示でセル内容が保たれること（ラウンドトリップ）をブラウザで確認。

## 10. 確定事項（レビュー承認済み）

1. **CodeMirror 導入**: CDN、CodeMirror 5（core + markdown + scheme モード）。
2. **支援レベル**: ハイライト + 括弧マッチ + インデントまで（オートコンプリートなし）。
3. **exercise の test-case UI**: input/output ペアの構造化リスト（追加/削除）。
4. **scene セル**: 既存を plain エディタで保持のみ。新規追加の種別セレクタには出さない。
