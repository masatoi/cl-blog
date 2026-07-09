# Recurya UI 多言語対応 (i18n) 設計仕様

- **日付**: 2026-07-10
- **状態**: 設計承認済み（実装計画未着手）
- **対象ブランチ（予定）**: `feat/i18n-ui-localization`

## 1. 背景と課題

ユーザーモデルには既に言語設定 (`users.language`, `:varchar 16`, デフォルト `"en"`, nullable) が存在し、アカウント設定画面 (`web/ui/account.lisp`) で 9 言語 (en/ja/zh/ko/es/fr/de/pt/it) から選択・保存できる。DB・セッション双方に永続化され、対応するルート／テストも通っている。

**しかしこの `language` 設定は UI レンダリングに一切使われていない。** UI 文字列はすべてテンプレートにハードコードされており、その大半が英語である一方、一部に日本語が混在している。結果として「UI の言語がそろっていない」状態になっている。

本仕様は、**保存済みの言語設定に応じて UI 文字列を切り替える i18n レイヤー**を導入し、UI の言語を統一する。

### 現状の規模（棚卸し結果）

`web/ui/*.lisp`（全 23 ファイル）＋ルート層 5 ファイルを横断調査した結果:

| 指標 | 値 |
|------|-----|
| 翻訳対象 UI 文字列（chrome） | **342 件** |
| 現在の言語内訳 | 英語 **325** / 日本語 **16** |
| 実態 | アプリはほぼ全面英語 UI で、日本語が 16 箇所だけ混入 |
| ホットスポット | reference.lisp(67), routes.lisp(36), course-form.lisp(29), notebook-form.lisp(27), courses.lisp(24) |
| 対象 0 ファイル | csrf / editor / styles / routes-novel / auth / oauth |

カテゴリ内訳: help-text(67), heading(58), other/format テンプレート(56), button(38), error-message(35), nav(31), page-title(20), form-label(19), placeholder(10), attr(7), flash-message(2)。

## 2. 決定事項（確定要件）

| 項目 | 決定 |
|------|------|
| 対応言語 | 当面は **日本語＋英語** の 2 言語。ただしアーキテクチャは**言語追加が容易な形**にする |
| ログイン済みユーザー | 保存済みの `language` 設定に従って描画 |
| 匿名ユーザー | **英語固定**（Accept-Language 検出なし）。言語変更はログイン後のアカウント設定経由 |
| 翻訳方式 | キー → 言語 → 訳文のカタログ（メッセージ辞書）方式 |
| カタログのキー方式 | **名前空間つきシンボリックキー**（`common.*` で重複排除、en/ja 両カタログ） |
| 言語切替 UI | **アカウント設定のみ**（ヘッダーに即時スイッチャーは置かない） |
| 342 件の日本語訳 | **エージェント下書き → ユーザーがレビュー**（既存日本語 16 件を語調の基準に） |

### スコープ境界（前提）

- **翻訳対象はアプリが用意する UI クローム**（ナビ・ボタン・ラベル・見出し・ヘルプ文・フラッシュ/エラーメッセージ・ページタイトル等）に限定。
- **ユーザー生成コンテンツ**（ノートブック/コースのタイトル・本文、セルのコード、レッスン文章、ノベルのシーンテキスト等）は**作成時の言語のまま**表示（自動翻訳しない）。

## 3. アーキテクチャ

### 3.1 新規 `i18n` モジュール

```
web/i18n/core.lisp   ; recurya/web/i18n/core
                     ;   *locale* / *default-locale* / *catalogs*
                     ;   register-message / defcatalog / tr
                     ;   available-locales / normalize-locale / known-key-p
                     ;   bind-locale (Lack ミドルウェア)
web/i18n/en.lisp     ; recurya/web/i18n/en : 英語カタログ登録（基準言語）
web/i18n/ja.lisp     ; recurya/web/i18n/ja : 日本語カタログ登録
```

- カタログ格納構造: `locale(keyword) → (hash-table: key(keyword) → テンプレート文字列)`。
- **言語追加 ＝ カタログファイル 1 枚追加**（`*catalogs*` に登録するだけ）。既存コードの変更不要。
- キーは名前空間つきキーワード。例: `:account.heading`, `:common.pagination.next`, `:layout.nav.notebooks`。
- `recurya.asd` に `web/i18n` モジュールを `web/routes`・`web/server` より前（依存関係の上流）に追加する。
  - ⚠️ これは **ASDF 構成変更**であり、初回に**コンテナ再起動が一度必要**（`CLAUDE.md` の「新モジュール追加」に該当）。以後のテンプレート編集・カタログ追記はホットリロード可。

### 3.2 ランタイム API (`tr`)

```lisp
(defvar *default-locale* :en
  "対応言語が見つからない/非対応時のフォールバック言語。")

(defvar *locale* :en
  "リクエスト単位で bind-locale が束縛する現在のロケール。")

(defun tr (key &rest format-args)
  "KEY を *locale* のカタログで引き、なければ *default-locale*(:en)、
   それでもなければ可視マーカー \"⟦key⟧\"（開発時は警告ログ）を返す。
   引いたテンプレートに (apply #'format nil template format-args) を適用。")
```

- **各言語が自前のテンプレートを持つ**ため、英語の複数形 `~:P` は日本語版テンプレートで単に省けばよい。CL `format` は余剰引数を無視し、`~N@*` で語順変更も可能なので、言語ごとに引数の使い方が異なっても動作する。
- 未定義キーは**空表示ではなく可視マーカー**にし、開発時に検知しやすくする（本番でも UI が空になるより安全）。
- 数値/日付ロケール処理は ja/en で共通のため今回は対象外（**将来拡張**として明記）。

### 3.3 ロケール束縛（リクエスト経路）

- `bind-locale` Lack ミドルウェアを新設。処理:
  1. `(getf env :lack.session)` からセッションを取得。
  2. `(gethash :user session)` → `(getf user :language)` を取得（セッション plist は既に `:language` を保持: `routes.lisp` の `user-dao->plist`）。
  3. `normalize-locale` で対応ロケールに正規化（匿名・非対応・nil は `*default-locale*` = `:en`）。
  4. `*locale*` をその値に束縛して `(funcall app env)` を実行。
- `web/server.lisp` の `build-app` の `lack/builder:builder` において **`:session` の直後**に挿入する:

  ```lisp
  (lack/builder:builder
   (:static ...)
   (:session :store (make-session-store))
   #'bind-locale              ; ← 追加（session の後、全描画をカバー）
   #'require-dashboard-auth
   #'csrf-with-skip
   #'require-real-handle
   :backtrace
   app)
  ```

- Spinneret のレンダリングはリクエストの動的エクステント内で同期実行されるため、`*locale*` の `let`/`progv` 束縛がテンプレートまで到達する。

### 3.4 フラッシュメッセージのキー化

- 現状 `account-update-handler`（`routes.lisp`）はリダイレクト URL に**英語をベタ書き**している:
  - `/account?message=Settings+updated`
  - `/account?error=Display+name+cannot+be+blank`
- → **メッセージキー渡し**に変更する:
  - `/account?msg=account.saved`
  - `/account?err=account.name_blank`
- 遷移先ハンドラ（例 `account-page-handler`）が受け取ったキーを**ホワイトリスト**（許可されたフラッシュキー → カタログキーの対応表）経由で検証し、`tr` で描画時に翻訳する。これにより:
  - URL に翻訳文が載らない。
  - `*locale*` が束縛済みの描画時点で正しい言語に翻訳される。
  - クエリ経由の任意キー注入を防ぐ（ホワイトリスト外は無視）。
- 実装時に `?message=` / `?error=` の全使用箇所を洗い出し、同方式に統一する。

### 3.5 テンプレート変換（342 件）

リテラルを `(tr :ns.key ...args)` に置換する。名前空間は棚卸しの推奨に沿う:

- `common.*` — pagination（prev/next/info）、actions（edit/delete/copy-link）、visibility pills（draft/published/private/unlisted/public）、共通ボタン（cancel/run/save/add）。**複数ファイルで重複する語をここに集約。**
- ページ/コンポーネント別: `layout.nav.* / layout.auth.*`, `errors.*`, `auth.login.*`, `onboarding.*`, `account.*`, `notebooks.dashboard.* / notebooks.form.* / notebooks.list.*`, `notebook.view.* / notebook.cell.* / notebook.cheatsheet.*`, `courses.dashboard.* / courses.form.* / courses.list.*`, `course.view.*`, `profile.*`, `wardlisp.{home,arena,playground,puzzle,reference}.*`, `novel.*`。
- バックエンド共有: `server.errors.*`（Forbidden/Unauthorized/Not found/Bad request 等）、`flash.*`。

#### 変換時の要注意点（棚卸しで判明）

1. **カタログ値は平文（HTML なし）を原則**とする。インライン `<code>` 周りに分割された文言（login の dev-stub バナー、onboarding の handle 案内、arena の decide-action 説明など、隣接文字列リテラルの連結）は、**Spinneret 側で DOM 構造を保ち、文言だけ `tr`** する。ユーザーデータは別ノードとして Spinneret に自動エスケープさせる。→ `:raw` 由来の XSS を回避する。
2. **JS 内可視テキスト**（novel の `— おわり —`、arena の `Turn `）は、Lisp 側 `tr` の値を `data-*` 属性でレンダリングし、インライン JS が `dataset` から読む。JS 内文字列直書きを廃止。
3. **`format` テンプレート**（`~A`/`~D`/`~:P` を含む）はカタログに**プレースホルダごとそのまま**格納し、`(tr :key args...)` で呼ぶ。例: `"Page ~A of ~A"`, `"Fuel: ~D | Cons: ~D | Depth: ~D"`, `"~D / ~D passed"`。
4. **ブランド語**（recurya / Google / GitHub）は翻訳文中でも原文のまま。ページタイトル `"recurya - ~A"` はテンプレートにブランドを残し、翻訳部分を引数で渡す。
5. **既存の日本語 16 件**（ヘッダーの「未ログイン」「ログイン」、notebook セル系ラベル、CSRF 画面、novel 終端メッセージ等）は、英語ベース(en) ＋ 日本語(ja) としてカタログ化する。既存の日本語テキストは ja カタログ値として再利用。→ これで英語ユーザーは英語、日本語ユーザーは日本語となり、**混在が解消**する。
6. **エンドニム**（言語名 English/日本語/中文/한국어…）は翻訳しない。`web/ui/account.lisp` の `*languages*` はそのまま維持（意図的な自言語表記）。
7. **reference.lisp の技術用語**（Integer/Float/Boolean/Symbol/Fuel/Cons/Depth/Output/Timeout 等）は、周辺の散文を訳しつつ、型名/リミット名は翻訳者判断で原語のままでも可（**レビュー対象**）。`<pre><code>` 例ブロック内の英語コメントはコード扱いで対象外。
8. **ユーザー生成コンテンツの補間**（`getf nb :title`, `@handle`, notebook/course タイトルを `<title>`/`<h1>` に埋める箇所）は翻訳しない。周辺のリテラルのみ翻訳し、補間値は runtime passthrough のまま。

### 3.6 アカウント設定の言語ドロップダウン

- 現状 9 言語を提示しているが、実際に翻訳を用意するのは en/ja のみ。他 7 言語を選ぶと英語にフォールバックし、UX 上わかりにくい。
- → ドロップダウンを **`available-locales` 駆動**に変更する。現状は En / 日本語 のみ表示し、**将来カタログを追加すれば自動的に選択肢が増える**。エンドニム対応表（`*languages*`）は表示名の引き当てに流用する。

## 4. テスト戦略

- **`tr` 単体テスト**（Rove）: ルックアップ / フォールバック連鎖（`*locale*` → `:en` → マーカー）/ 引数補間 / 未対応ロケール正規化 / 未定義キー / 匿名時の `:en`。
- **カタログ・パリティ検査**: `:en` の全キーが `:ja` に存在（逆も）を検証し、欠落があれば CI で落とす。→ **「訳し漏れ」の安全網**。
- **ハンドラ / 描画テスト**（`tests/web/*.lisp`）: `*locale*` を `:ja` に束縛して `account:render` / `layout:header` 等が日本語を含むこと、`:en` で英語を含むこと、匿名 → 英語を assert。ミドルウェア配線は `scripts/request-test.sh` でブラウザレス E2E 検証。
- **既存テストの更新**: `account-page-displays-saved-settings` は "fr" 選択を検証しており、ドロップダウン縮小（en/ja のみ）で**要更新**。他の英語リテラルを直接検証しているテストも、キー化に伴い `*locale*=:en` 前提へ更新する。

## 5. 展開順（実装計画で具体化）

- **Phase 0 — 機構**: `web/i18n` モジュール（`core`/`en`/`ja`）+ `tr` + `bind-locale` + `recurya.asd` 更新 + `tr` 単体/パリティテスト。コンテナ再起動で新モジュールをロード。
- **Phase 1 — パイロット**: `layout`（ヘッダ/ナビ＝最も目立つ混在箇所）+ `account`（設定画面）を en/ja 完全変換 ＋ 描画/E2E テストで機構を実証。
- **Phase 2..N — ファンアウト**: 残りファイルを名前空間グループ単位で変換。per-file 手順は「抽出 → キー置換 → en/ja カタログ登録」。その後、parity ＋ 描画 verify パス。可視性/流量順に進める。342 件の日本語訳はエージェントで一括下書きし、**ユーザーがレビュー**（既存日本語 16 件を語調の基準に）。
- **Phase 終盤 — 仕上げ**: フラッシュのキー化 / JS 埋め込みテキスト対応 / アカウント言語ドロップダウン縮小 / 全テスト＋`request-test.sh` / カタログ・パリティ緑。

## 6. 不採用案

- **案 B: ページ単位で言語別レンダ関数を複製**（`render-en` / `render-ja`）。重複が爆発し保守不能・言語追加が困難なため不採用。
- **英語文字列を直接キー(msgid)にする方式**。着手は速いが、文脈違いの同一英語の衝突や、長い `format` テンプレートがキーになる難があり、将来の多言語化・再利用性で名前空間キーに劣るため不採用。
- **ヘッダー即時言語スイッチャー**。匿名英語固定＋アカウント設定変更で要件を満たすため、実装最小化の観点で今回は不採用（将来追加可能）。

## 7. 将来拡張

- 対応言語の追加（`web/i18n/<lang>.lisp` を 1 枚追加 ＋ アカウントドロップダウンに自動出現）。
- ヘッダー言語スイッチャー（匿名でも切替・セッション/Cookie 保持）。
- 数値/日付/複数形のロケール対応（CLDR 相当）。
- Accept-Language ヘッダーによる匿名ユーザーの初期言語推定。
