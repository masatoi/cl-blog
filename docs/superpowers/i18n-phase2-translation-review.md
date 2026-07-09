# Phase 2 翻訳レビュー — recurya i18n（20ファイル・287キー）

> 下書き（エージェント生成）。**en = 現行の英語リテラル逐語**（英語表示は非退行）、**ja = 提案訳**。
> パリティ緑・en フォールバック安全なので、この下書きのまま適用しても表示は壊れません。ja の文言だけ後から差し替え可能です。

## ⚠️ 要判断（優先レビュー）

### A. reference.lisp の型名（8件） — 日本語化する？英語のまま？
学習者向けに型名を日本語にするか、Lisp 慣習の英語表記を残すか。現在の下書きは日本語訳:

| key | en | ja(案) |
|---|---|---|
| wardlisp.reference.type_integer | Integer | 整数 |
| wardlisp.reference.type_float | Float | 浮動小数点数 |
| wardlisp.reference.type_boolean | Boolean | 真偽値 |
| wardlisp.reference.type_symbol | Symbol | シンボル |
| wardlisp.reference.type_pair | Pair | ペア |
| wardlisp.reference.type_list | List | リスト |
| wardlisp.reference.type_nil | Nil | Nil |
| wardlisp.reference.type_function | Function | 関数 |

### B. 統合で検出された調整候補（5件）

- notebook.cell.error_in_cell: input entry had en identical to the Japanese source literal ('セル「~A」でエラー: ~A'). Per the entry's own note I set en to the natural English base 'Error in cell "~A": ~A' (first ~A = cell id, kept verbatim) so English chrome renders in English. ja unchanged.
- en NOT verbatim-identical to a current UI literal because the SOURCE literal is already Japanese (deviation from the en=verbatim rule is intentional — en is a newly-authored English translation): notebook.cell.reset (リセット→Reset), notebook.cell.reset_title, notebook.cell.scene_error_prefix, notebook.cell.scene_error_suffix, notebook.cell.view_solution, notebook.cell.solution_locked, notebook.cell.all_tests_passed, notebook.cell.some_tests_failed, notebook.cell.reset_hint_origin, notebook.cell.reset_hint_edited, notebook.cheatsheet.heading, errors.csrf.body, novel.end. notebook.cheatsheet.body is a mixed EN/JA source literal, so both en and ja are partially re-normalized.
- No duplicate-key value collisions: every shared string maps to a single common.* key; file-local variants use distinct keys. Note two near-duplicate ja values on distinct keys (intentional, NOT a conflict): course_form.visibility_unlisted ja '限定公開（リンクを知っている全員）' vs notebook.form.visibility_unlisted ja '限定公開（リンクを知っている人のみ）'.
- Inconsistent ja for the same English source 'Print Output' across distinct keys: wardlisp.puzzle.print_output_label ja 'プリント出力' vs wardlisp.playground.print_output_label ja '出力'. Distinct keys so no hard collision, but reviewer should decide on one rendering.
- common.pagination.prev/next: courses.lisp and notebooks-dashboard.lisp source literals are icon-based (' Previous' with leading space + FA arrow icon / 'Next ' with trailing space), which do NOT match the common '← Previous'/'Next →' glyph forms. courses.lisp was mapped to the common keys (values differ from source) while notebooks-dashboard.lisp uses file-local keys — reconcile which handling is correct before find-and-replace.

### C. その他の要レビュー項目（曖昧フラグ付き）

- reference.lisp: Integer/Float/Boolean/Symbol/Pair/List/Nil/Function -> 整数/浮動小数点数/真偽値/シンボル/ペア/リスト/Nil/関数 (Lisp type names, all flagged ambiguous; user may prefer keeping English)
- reference.lisp: Fuel/Cons/Depth/Output/Timeout -> 燃料/コンス/深さ/出力/タイムアウト (WardLisp resource terms, ambiguous; may stay English)
- routes.lisp: Forbidden/Unauthorized/Not found/Bad request -> 権限がありません/認証が必要です/見つかりません/不正なリクエストです (terse HTTP status bodies reused across many handlers; translator may keep English)
- routes.lisp: 'Invalid index'/'Index out of range' -> 無効なインデックスです/インデックスが範囲外です (technical; 'index' may stay English)
- routes.lisp: server.db.slug_taken/save_failed 'That ~A slug...' -> その~Aの... (~A injects English 'notebook'/'course'; entity noun likely needs separate localization to read naturally in ja)
- routes.lisp: auth.login.error.provider_not_configured 'OAuth provider ~A is not configured.' -> OAuthプロバイダー ~A は設定されていません。 (~A = provider id kept; 'OAuth' verbatim)
- routes.lisp: server.forms.title_required/body_required and onboarding.handle.error.* -> namespaces are proposals (messages emitted here but rendered by form/onboarding UI); reviewer may relocate; verify handle-rule wording matches valid-handle-p
- course-form.lisp / notebook-form.lisp: 'L~A' -> 'L~A' and 'recurya - ~A' -> 'recurya - ~A' kept verbatim (line badge / brand browser title; ambiguous)
- notebook-form.lisp: placeholder_body '===prose===\nWrite here...' -> '===prose===\nここに入力...' (===prose=== token verbatim; literal backslash-n, not a newline)
- notebook-form.lisp: cheatsheet.heading source ALREADY Japanese 'セル区切りチートシート'; en newly authored 'Cell delimiter cheatsheet' (deviates from en=verbatim)
- notebook-form.lisp: cheatsheet.body — large mixed EN/JA single literal; all cell-syntax tokens/code kept verbatim, only hint prose localized; verify normalization both directions
- courses.lisp: pagination source ' Previous'/'Next ' are icon-based (space + FA icon) but mapped to common.pagination.prev/next (← / → glyph forms) — reconcile before replace
- notebooks-dashboard.lisp: table.published 'Published' -> 公開日時 (date column, distinct from common.visibility.published 公開済み); table.actions -> 操作 (file-local)
- notebooks-dashboard.lisp: pagination.previous ' Previous' -> ' 前へ', pagination.next 'Next ' -> '次へ ' (icon-based, leading/trailing spaces significant; kept file-local not common)
- notebook.lisp: many labels source ALREADY Japanese (reset, reset_title, view_solution, solution_locked, all_tests_passed, some_tests_failed, reset_hint_origin/edited, scene_error_prefix/suffix) — en newly authored English base
- notebook.lisp: error_in_cell input en held Japanese; set en to 'Error in cell "~A": ~A' per its note (first ~A = cell id verbatim, second ~A = error msg)
- notebook.lisp: split prose expected ' — expected ' / got ' got ' (leading/trailing spaces significant), error_placeholder '<error>' -> '<エラー>', pass_badge 'PASS' -> 合格 (may stay 'PASS'), metrics 'Fuel: ~D \| Cons: ~D \| Depth: ~D' kept English
- arena.lisp: page_title 'WardLisp Arena', heading 'Bot Arena', desc_actions (mostly 'up 'down... code symbols), turn_label 'Turn ' (JS-embedded, trailing space), state_label 'state' (may be code var name) — all ambiguous, may stay English
- puzzle.lisp / playground.lisp: print_output_label inconsistent (プリント出力 vs 出力); metrics 'Fuel: ~D \| Cons: ~D \| Depth: ~D' kept English (may localize 燃料/コンス/深さ)
- course-list.lisp: card_meta '~@[~A~]~@[ · ~A notebook~:P~]~@[ · ~A~]' -> dropped ~:P plural in ja, kept all ~@[ conditionals in order (plural/format edge case — verify)
- onboarding.lisp: handle_help_1/2/3 and current_handle_prefix/suffix are split prose around inline <code>; ja reworded to read naturally when concatenated — verify word order and significant leading/trailing spaces
- login.lisp: dev_stub.reuse_prefix/suffix split prose reordered in ja (moved 'Google/GitHub に接続せず' into prefix around the <code>email); dev_stub.title 'Dev OAuth stub is active.' may stay English
- errors.lisp: csrf.body source ALREADY Japanese; en newly authored (deviates from en=verbatim)
- novel.lisp: novel.end source ALREADY Japanese '— おわり —' (embedded JS string literal, handled separately); en restores '— The End —'
- routes-wardlisp.lisp: not_found_page/fragment contain HTML markup ('<h1>...</h1>', '<div class="error">...</div>') — tags/class preserved, only visible text localized
- course.lisp: passed_count '~A passed' -> '~A 問正解' (ambiguous; alternatives '~A 通過' / '~A 完了' — needs review)

## 共通語彙 common.*（17件）

| key | en | ja |
|---|---|---|
| common.buttons.up | Up | 上へ |
| common.buttons.down | Down | 下へ |
| common.buttons.remove | Remove | 削除 |
| common.buttons.add | Add | 追加 |
| common.buttons.cancel | Cancel | キャンセル |
| common.buttons.run | Run | 実行 |
| common.pagination.prev | ← Previous | ← 前へ |
| common.pagination.next | Next → | 次へ → |
| common.pagination.info | Page ~A of ~A | ~A / ~A ページ |
| common.actions.edit | Edit | 編集 |
| common.actions.delete | Delete | 削除 |
| common.actions.copy_link | Copy link | リンクをコピー |
| common.visibility.draft | Draft | 下書き |
| common.visibility.published | Published | 公開済み |
| common.visibility.private | Private | 非公開 |
| common.visibility.unlisted | Unlisted | 限定公開 |
| common.visibility.public | Public | 全体公開 |

## ファイル別 全訳

### reference.lisp（67件）
| key | en | ja | ⚑ |
|---|---|---|---|
| wardlisp.reference.page_title | WardLisp Reference | WardLisp リファレンス |  |
| wardlisp.reference.breadcrumb_reference |  / Reference |  / リファレンス |  |
| wardlisp.reference.heading | WardLisp Reference | WardLisp リファレンス |  |
| wardlisp.reference.subtitle | A safe, restricted Lisp dialect for learning | 学習用の安全で制限された Lisp 方言 |  |
| wardlisp.reference.section_types | Types | 型 |  |
| wardlisp.reference.section_special_forms | Special Forms | 特殊形式 |  |
| wardlisp.reference.section_builtins | Built-in Functions | 組み込み関数 |  |
| wardlisp.reference.section_resource_limits | Resource Limits | リソース制限 |  |
| wardlisp.reference.section_examples | Examples | 例 |  |
| wardlisp.reference.subsection_arithmetic | Arithmetic | 算術演算 |  |
| wardlisp.reference.subsection_comparison | Comparison | 比較 |  |
| wardlisp.reference.subsection_list_operations | List Operations | リスト操作 |  |
| wardlisp.reference.subsection_type_predicates | Type Predicates | 型述語 |  |
| wardlisp.reference.subsection_utility | Utility | ユーティリティ |  |
| wardlisp.reference.example_recursive | Recursive function | 再帰関数 |  |
| wardlisp.reference.example_higher_order | Higher-order function | 高階関数 |  |
| wardlisp.reference.example_alists | Working with alists | 連想リストの操作 |  |
| wardlisp.reference.types_col_type | Type | 型 |  |
| wardlisp.reference.types_col_examples | Examples | 例 |  |
| wardlisp.reference.types_col_notes | Notes | 備考 |  |
| wardlisp.reference.type_integer | Integer | 整数 | ⚑ |
| wardlisp.reference.type_float | Float | 浮動小数点数 | ⚑ |
| wardlisp.reference.type_boolean | Boolean | 真偽値 | ⚑ |
| wardlisp.reference.type_symbol | Symbol | シンボル | ⚑ |
| wardlisp.reference.type_pair | Pair | ペア | ⚑ |
| wardlisp.reference.type_list | List | リスト | ⚑ |
| wardlisp.reference.type_nil | Nil | Nil | ⚑ |
| wardlisp.reference.type_function | Function | 関数 | ⚑ |
| wardlisp.reference.type_integer_note | Whole numbers | 整数 |  |
| wardlisp.reference.type_float_note | Double-precision floating point | 倍精度浮動小数点数 |  |
| wardlisp.reference.type_boolean_note | True and false | 真と偽 |  |
| wardlisp.reference.type_symbol_note | Named values (quote to use as data) | 名前付きの値（データとして使うにはクォートする） |  |
| wardlisp.reference.type_pair_note | Two-element pair (car/cdr) | 2要素のペア（car/cdr） |  |
| wardlisp.reference.type_list_note | Pairs ending in nil | nil で終わるペアの連なり |  |
| wardlisp.reference.type_nil_note | Empty list, false value | 空リスト、偽値 |  |
| wardlisp.reference.type_function_note | Closures with lexical scope | レキシカルスコープを持つクロージャ |  |
| wardlisp.reference.sf_define_desc | Bind a value to a name in the current scope. | 現在のスコープで名前に値を束縛する。 |  |
| wardlisp.reference.sf_define_fn_desc | Shorthand for defining a function. | 関数を定義するための省略記法。 |  |
| wardlisp.reference.sf_lambda_desc | Create an anonymous function (closure). | 無名関数（クロージャ）を生成する。 |  |
| wardlisp.reference.sf_if_desc | Conditional. Only nil is falsy. | 条件分岐。偽となるのは nil のみ。 |  |
| wardlisp.reference.sf_let_desc | Parallel bindings. All values evaluated before binding. | 並列束縛。すべての値を束縛前に評価する。 |  |
| wardlisp.reference.sf_letstar_desc | Sequential bindings. Each binding sees previous ones. | 逐次束縛。各束縛は直前までの束縛を参照できる。 |  |
| wardlisp.reference.sf_begin_desc | Evaluate expressions in sequence, return last. | 式を順に評価し、最後の値を返す。 |  |
| wardlisp.reference.sf_quote_desc | Return expression unevaluated. | 式を評価せずにそのまま返す。 |  |
| wardlisp.reference.sf_and_desc | Short-circuit logical AND. | 短絡評価の論理積（AND）。 |  |
| wardlisp.reference.sf_or_desc | Short-circuit logical OR. | 短絡評価の論理和（OR）。 |  |
| wardlisp.reference.sf_cond_desc | Multi-branch conditional. First true test's body is evaluated. | 多分岐の条件式。最初に真となったテストの本体を評価する。 |  |
| wardlisp.reference.sf_apply_desc | Apply function to a list of arguments. | 引数のリストに関数を適用する。 |  |
| wardlisp.reference.limits_intro | All executions are sandboxed with these limits: | すべての実行は以下の制限のもとサンドボックス化されます： |  |
| wardlisp.reference.limits_col_resource | Resource | リソース |  |
| wardlisp.reference.limits_col_limit | Limit | 制限 |  |
| wardlisp.reference.limits_col_description | Description | 説明 |  |
| wardlisp.reference.limit_fuel | Fuel | 燃料 | ⚑ |
| wardlisp.reference.limit_cons | Cons | コンス | ⚑ |
| wardlisp.reference.limit_depth | Depth | 深さ | ⚑ |
| wardlisp.reference.limit_output | Output | 出力 | ⚑ |
| wardlisp.reference.limit_timeout | Timeout | タイムアウト | ⚑ |
| wardlisp.reference.limit_fuel_value | 100,000 steps | 100,000 ステップ |  |
| wardlisp.reference.limit_cons_value | 10,000 cells | 10,000 セル |  |
| wardlisp.reference.limit_depth_value | 200 levels | 200 レベル |  |
| wardlisp.reference.limit_output_value | 10,000 chars | 10,000 文字 |  |
| wardlisp.reference.limit_timeout_value | 5 seconds | 5 秒 |  |
| wardlisp.reference.limit_fuel_desc | Maximum evaluation steps | 最大評価ステップ数 |  |
| wardlisp.reference.limit_cons_desc | Maximum list allocations | 最大リスト割り当て数 |  |
| wardlisp.reference.limit_depth_desc | Maximum recursion depth | 最大再帰深度 |  |
| wardlisp.reference.limit_output_desc | Maximum printed output | 最大出力文字数 |  |
| wardlisp.reference.limit_timeout_desc | Wall-clock time limit | 実時間の上限 |  |

### course-form.lisp（30件）
*reused common:* common.buttons.up, common.buttons.down, common.buttons.remove, common.buttons.add, common.buttons.cancel, common.visibility.draft, common.visibility.published

| key | en | ja | ⚑ |
|---|---|---|---|
| course_form.notebooks_heading | Notebooks | ノートブック |  |
| course_form.notebooks_empty | No notebooks attached yet. Add one below. | まだノートブックが追加されていません。下から追加してください。 |  |
| common.buttons.up | Up | 上へ |  |
| common.buttons.down | Down | 下へ |  |
| common.buttons.remove | Remove | 削除 |  |
| course_form.no_more_notebooks | No more notebooks available to add. | 追加できるノートブックはこれ以上ありません。 |  |
| course_form.add_notebook_label | Add notebook | ノートブックを追加 |  |
| common.buttons.add | Add | 追加 |  |
| course_form.page_title_edit | Edit Course | コースを編集 |  |
| course_form.page_title_new | New Course | 新規コース |  |
| course_form.browser_title | recurya - ~A | recurya - ~A | ⚑ |
| course_form.validation_errors_heading | Validation errors: | 入力エラー: |  |
| course_form.error_line_prefix | L~A | L~A | ⚑ |
| course_form.title_label | Title | タイトル |  |
| course_form.title_placeholder | Course title | コースのタイトル |  |
| course_form.slug_label | Slug | スラッグ |  |
| course_form.slug_placeholder | auto-generated-from-title | auto-generated-from-title | ⚑ |
| course_form.slug_hint | Leave blank to auto-generate from title. | 空欄のままにするとタイトルから自動生成されます。 |  |
| course_form.summary_label | Summary | 概要 |  |
| course_form.summary_placeholder | Short summary (max 500 chars) | 短い概要（最大500文字） |  |
| course_form.status_label | Status | ステータス |  |
| common.visibility.draft | Draft | 下書き |  |
| common.visibility.published | Published | 公開済み |  |
| course_form.visibility_label | Visibility | 公開範囲 |  |
| course_form.visibility_private | Private (only you) | 非公開（自分のみ） |  |
| course_form.visibility_unlisted | Unlisted (anyone with the link) | 限定公開（リンクを知っている全員） |  |
| course_form.visibility_public | Public (anyone) | 全体公開（誰でも） |  |
| course_form.submit_update | Update Course | コースを更新 |  |
| course_form.submit_create | Create Course | コースを作成 |  |
| common.buttons.cancel | Cancel | キャンセル |  |

### notebook-form.lisp（25件）
*reused common:* common.visibility.draft, common.visibility.published, common.buttons.cancel

| key | en | ja | ⚑ |
|---|---|---|---|
| notebook.form.page_title_edit | Edit Notebook | ノートブックを編集 |  |
| notebook.form.page_title_new | New Notebook | 新しいノートブック |  |
| notebook.form.browser_title | recurya - ~A | recurya - ~A |  |
| notebook.form.validation_errors | Validation errors: | 入力エラー: |  |
| notebook.form.error_line | L~A | L~A | ⚑ |
| notebook.form.label_title | Title | タイトル |  |
| notebook.form.placeholder_title | Notebook title | ノートブックのタイトル |  |
| notebook.form.label_slug | Slug | スラッグ |  |
| notebook.form.hint_slug | Leave blank to auto-generate from title. | 空欄にするとタイトルから自動生成されます。 |  |
| notebook.form.label_summary | Summary | 概要 |  |
| notebook.form.placeholder_summary | Short summary (max 500 chars) | 短い概要（最大500文字） |  |
| notebook.form.label_body | Body | 本文 |  |
| notebook.form.placeholder_body | ===prose===\nWrite here... | ===prose===\nここに入力... | ⚑ |
| notebook.form.label_status | Status | ステータス |  |
| common.visibility.draft | Draft | 下書き |  |
| common.visibility.published | Published | 公開済み |  |
| notebook.form.label_visibility | Visibility | 公開範囲 |  |
| notebook.form.visibility_private | Private (only you) | 非公開（自分のみ） |  |
| notebook.form.visibility_unlisted | Unlisted (anyone with the link) | 限定公開（リンクを知っている人のみ） |  |
| notebook.form.visibility_public | Public (anyone) | 全体公開（誰でも） |  |
| notebook.form.submit_update | Update Notebook | ノートブックを更新 |  |
| notebook.form.submit_create | Create Notebook | ノートブックを作成 |  |
| common.buttons.cancel | Cancel | キャンセル |  |
| notebook.cheatsheet.heading | Cell delimiter cheatsheet | セル区切りチートシート | ⚑ |
| notebook.cheatsheet.body | ===prose===⏎Markdown text — **bold**, *italic*, `code`, links.⏎⏎===eval===⏎(+ 1 2)⏎⏎===exercise: description===⏎; code for the user to fill in⏎⏎===expect: description===⏎expected value (literal)⏎⏎===expect===⏎input: (foo 1 2)⏎output: 3 | ===prose===⏎Markdownテキスト — **太字**、*斜体*、`code`、リンク。⏎⏎===eval===⏎(+ 1 2)⏎⏎===exercise: 説明文===⏎; ユーザが穴埋めするコード⏎⏎===expect: 説明文===⏎期待値（リテラル）⏎⏎===expect===⏎input: (foo 1 2)⏎output: 3 | ⚑ |

### routes.lisp（22件）
| key | en | ja | ⚑ |
|---|---|---|---|
| server.errors.forbidden | Forbidden | 権限がありません | ⚑ |
| server.errors.unauthorized | Unauthorized | 認証が必要です | ⚑ |
| server.errors.not_found | Not found | 見つかりません | ⚑ |
| server.errors.bad_request | Bad request | 不正なリクエストです | ⚑ |
| server.errors.notebook_not_found | Notebook not found | ノートブックが見つかりません |  |
| server.errors.invalid_index | Invalid index | 無効なインデックスです | ⚑ |
| server.errors.index_out_of_range | Index out of range | インデックスが範囲外です | ⚑ |
| server.errors.cannot_run_cell | Cannot run this cell | このセルは実行できません |  |
| server.errors.notebook_not_exist | Selected notebook does not exist. | 選択したノートブックは存在しません。 |  |
| server.errors.only_own_notebooks | You can only add your own notebooks. | 自分のノートブックのみ追加できます。 |  |
| server.errors.notebook_already_attached | This notebook is already attached. | このノートブックは既に追加されています。 |  |
| server.db.slug_taken | That ~A slug is already taken. Please choose a different slug. | その~Aのスラッグは既に使用されています。別のスラッグを選択してください。 | ⚑ |
| server.db.save_failed | Could not save the ~A due to a database error. Please try again. | データベースエラーのため~Aを保存できませんでした。もう一度お試しください。 | ⚑ |
| auth.login.error.provider_not_configured | OAuth provider ~A is not configured. | OAuthプロバイダー ~A は設定されていません。 | ⚑ |
| auth.login.error.session_expired | Sign-in session expired. Please try again. | サインインセッションの有効期限が切れました。もう一度お試しください。 |  |
| auth.login.error.no_verified_email | Could not retrieve a verified email from the provider. | プロバイダーから確認済みのメールアドレスを取得できませんでした。 |  |
| auth.login.error.login_failed | OAuth login failed. Please try again. | OAuthログインに失敗しました。もう一度お試しください。 |  |
| server.forms.title_required | Title is required. | タイトルは必須です。 | ⚑ |
| server.forms.body_required | Body is required. | 本文は必須です。 | ⚑ |
| onboarding.handle.error.invalid | Invalid handle. Use 3-64 lowercase letters, digits or hyphens, and start/end with a letter or digit. | 無効なハンドルです。3〜64文字の小文字英字・数字・ハイフンを使用し、先頭と末尾は英字または数字にしてください。 | ⚑ |
| onboarding.handle.error.reserved | That handle is reserved. Please choose a different one. | そのハンドルは予約されています。別のものを選択してください。 |  |
| onboarding.handle.error.taken | That handle is already taken. Please choose a different one. | そのハンドルは既に使用されています。別のものを選択してください。 |  |

### courses.lisp（20件）
*reused common:* common.visibility.draft, common.visibility.private, common.visibility.unlisted, common.visibility.public, common.actions.edit, common.actions.delete, common.actions.copy_link, common.pagination.info, common.pagination.prev, common.pagination.next

| key | en | ja | ⚑ |
|---|---|---|---|
| courses.page_title | recurya - My Courses | recurya - マイコース |  |
| courses.heading | My Courses | マイコース |  |
| courses.subtitle | Manage your authored courses. | 作成したコースを管理します。 |  |
| courses.new_course | + New Course | + 新規コース |  |
| courses.table.title | Title | タイトル |  |
| courses.table.status | Status | ステータス |  |
| courses.table.notebooks | Notebooks | ノートブック |  |
| courses.table.created | Created | 作成日 |  |
| courses.table.actions | Actions | 操作 |  |
| courses.empty | No courses yet. Create your first one! | コースがまだありません。最初のコースを作成しましょう！ |  |
| common.visibility.draft | Draft | 下書き |  |
| common.visibility.private | Private | 非公開 |  |
| common.visibility.unlisted | Unlisted | 限定公開 |  |
| common.visibility.public | Public | 全体公開 |  |
| common.actions.edit | Edit | 編集 |  |
| common.actions.delete | Delete | 削除 |  |
| common.actions.copy_link | Copy link | リンクをコピー |  |
| common.pagination.info | Page ~A of ~A | ~A / ~A ページ |  |
| common.pagination.prev | ← Previous | ← 前へ | ⚑ |
| common.pagination.next | Next → | 次へ → | ⚑ |

### notebooks-dashboard.lisp（20件）
*reused common:* common.visibility.draft, common.visibility.private, common.visibility.unlisted, common.visibility.public, common.actions.edit, common.actions.delete, common.actions.copy_link, common.pagination.info

| key | en | ja | ⚑ |
|---|---|---|---|
| notebooks_dashboard.page_title | recurya - My Notebooks | recurya - マイノートブック |  |
| notebooks_dashboard.heading | My Notebooks | マイノートブック |  |
| notebooks_dashboard.subtitle | Manage your user-authored notebooks. | 自分が作成したノートブックを管理します。 |  |
| notebooks_dashboard.new_button | + New Notebook | + 新規ノートブック |  |
| notebooks_dashboard.table.title | Title | タイトル |  |
| notebooks_dashboard.table.status | Status | ステータス |  |
| notebooks_dashboard.table.published | Published | 公開日時 | ⚑ |
| notebooks_dashboard.table.created | Created | 作成日時 |  |
| notebooks_dashboard.table.actions | Actions | 操作 | ⚑ |
| common.visibility.draft | Draft | 下書き |  |
| common.visibility.private | Private | 非公開 |  |
| common.visibility.unlisted | Unlisted | 限定公開 |  |
| common.visibility.public | Public | 全体公開 |  |
| common.actions.edit | Edit | 編集 |  |
| common.actions.delete | Delete | 削除 |  |
| common.actions.copy_link | Copy link | リンクをコピー |  |
| common.pagination.info | Page ~A of ~A | ~A / ~A ページ |  |
| notebooks_dashboard.pagination.previous |  Previous |  前へ | ⚑ |
| notebooks_dashboard.pagination.next | Next  | 次へ  | ⚑ |
| notebooks_dashboard.empty_state | No notebooks yet. Create your first one! | ノートブックはまだありません。最初の1冊を作成しましょう! |  |

### notebook.lisp（20件）
*reused common:* common.buttons.run, common.pagination.prev, common.pagination.next

| key | en | ja | ⚑ |
|---|---|---|---|
| common.buttons.run | Run | 実行 |  |
| notebook.cell.reset | Reset | リセット |  |
| notebook.cell.reset_title | Reset the cell to its initial code | セルを初期コードに戻す |  |
| notebook.cell.done_badge | ✓ done | ✓ 完了 |  |
| notebook.cell.scene_error_prefix | (Cannot display this scene:  | （このシーンを表示できません:  | ⚑ |
| notebook.cell.scene_error_suffix | ) | ） | ⚑ |
| notebook.cell.view_solution | View solution | 解答を見る |  |
| notebook.cell.solution_locked | 🔒 The solution appears once you solve the exercise above | 🔒 直前の演習に正解すると解答が表示されます |  |
| common.pagination.prev | ← Previous | ← 前へ |  |
| common.pagination.next | Next → | 次へ → |  |
| notebook.cell.expected |  — expected  |  — 期待値  | ⚑ |
| notebook.cell.got |  got  |  実際  | ⚑ |
| notebook.cell.error_placeholder | <error> | <エラー> | ⚑ |
| notebook.cell.pass_badge | PASS | 合格 | ⚑ |
| notebook.cell.all_tests_passed |  All tests passed |  全テスト合格 |  |
| notebook.cell.some_tests_failed | Some tests failed | 一部のテストが失敗しました |  |
| notebook.cell.error_in_cell | セル「~A」でエラー: ~A | セル「~A」でエラー: ~A | ⚑ |
| notebook.cell.reset_hint_origin | 💡 You can restore the initial code with the “Reset” button on the cell above. | 💡 上のセル「リセット」ボタンで初期コードに戻せます。 |  |
| notebook.cell.reset_hint_edited | 💡 If you have edited the cell above, use its “Reset” button to restore the initial code. | 💡 上のセルを編集している場合、「リセット」ボタンで初期コードに戻せます。 |  |
| notebook.cell.metrics | Fuel: ~D \| Cons: ~D \| Depth: ~D | Fuel: ~D \| Cons: ~D \| Depth: ~D | ⚑ |

### arena.lisp（17件）
| key | en | ja | ⚑ |
|---|---|---|---|
| wardlisp.arena.page_title | WardLisp Arena | WardLisp アリーナ | ⚑ |
| wardlisp.arena.breadcrumb_arena |  / Arena |  / アリーナ |  |
| wardlisp.arena.heading | Bot Arena | ボットアリーナ | ⚑ |
| wardlisp.arena.desc_intro | Write a (decide-action state) function that returns an action symbol:  | アクションシンボルを返す (decide-action state) 関数を書いてください:  |  |
| wardlisp.arena.desc_actions | 'up, 'down, 'left, 'right, 'wait, or 'pickup.  | 'up、'down、'left、'right、'wait、または 'pickup。  | ⚑ |
| wardlisp.arena.desc_compete | Compete against a greedy enemy bot to collect resources on a 7x7 grid over 20 turns. | 貪欲な敵ボットと競い、7x7 のグリッド上で 20 ターンにわたってリソースを集めましょう。 |  |
| wardlisp.arena.editor_placeholder | Write your decide-action function... | decide-action 関数を書いてください... |  |
| wardlisp.arena.run_button | Run Simulation | シミュレーション実行 |  |
| wardlisp.arena.score_bot | Bot: ~D | ボット: ~D |  |
| wardlisp.arena.score_enemy | Enemy: ~D | 敵: ~D |  |
| wardlisp.arena.prev_button | &laquo; Prev | &laquo; 前 |  |
| wardlisp.arena.next_button | Next &raquo; | 次 &raquo; |  |
| wardlisp.arena.turn_display | Turn 0 | ターン 0 |  |
| wardlisp.arena.turn_label | Turn  | ターン  | ⚑ |
| wardlisp.arena.output_label | Output | 出力 |  |
| wardlisp.arena.state_label | state | 状態 | ⚑ |
| wardlisp.arena.metrics | Total fuel: ~D \| Frames: ~D | 総燃料: ~D \| フレーム数: ~D |  |

### puzzle.lisp（11件）
*reused common:* common.buttons.run

| key | en | ja | ⚑ |
|---|---|---|---|
| wardlisp.puzzle.page_title | ~A - WardLisp | ~A - WardLisp |  |
| wardlisp.puzzle.breadcrumb_puzzles | Puzzles | パズル |  |
| wardlisp.puzzle.test_cases_heading | Test Cases | テストケース |  |
| wardlisp.puzzle.code_placeholder | Write your solution here... | ここに解答を書いてください... |  |
| common.buttons.run | Run | 実行 |  |
| wardlisp.puzzle.print_output_label | Print Output | プリント出力 | ⚑ |
| wardlisp.puzzle.result_label | Result | 結果 |  |
| wardlisp.puzzle.passed_count | ~D / ~D passed | ~D / ~D 合格 |  |
| wardlisp.puzzle.test_error |  error: ~A |  エラー: ~A |  |
| wardlisp.puzzle.test_expected_got |  expected ~A, got ~A |  期待値 ~A、実際 ~A |  |
| wardlisp.puzzle.metrics | Fuel: ~D \| Cons: ~D \| Depth: ~D | Fuel: ~D \| Cons: ~D \| Depth: ~D | ⚑ |

### onboarding.lisp（11件）
| key | en | ja | ⚑ |
|---|---|---|---|
| onboarding.page_title | Choose your handle - recurya | ハンドルを選択 - recurya |  |
| onboarding.app_name | Welcome to recurya | recurya へようこそ |  |
| onboarding.heading | Choose your handle | ハンドルを選択 |  |
| onboarding.handle_help_1 | Your handle is the permanent URL for your profile and the things you publish.  | ハンドルは、あなたのプロフィールや公開物の恒久的な URL になります。 | ⚑ |
| onboarding.handle_help_2 | It must be 3 to 64 characters, use lowercase letters, digits and hyphens,  | 3～64 文字で、英小文字・数字・ハイフンを使用し、 | ⚑ |
| onboarding.handle_help_3 | and start and end with a letter or digit. | 先頭と末尾は英字または数字にする必要があります。 | ⚑ |
| onboarding.current_handle_prefix | Your temporary handle is  | 現在の仮ハンドルは  | ⚑ |
| onboarding.current_handle_suffix | . Pick a permanent one below. |  です。以下で恒久的なハンドルを選択してください。 | ⚑ |
| onboarding.field_label_handle | Handle | ハンドル |  |
| onboarding.field_hint | Allowed characters: a-z, 0-9, hyphen. Cannot start or end with a hyphen. | 使用可能な文字: a-z、0-9、ハイフン。先頭と末尾にハイフンは使えません。 |  |
| onboarding.submit_button | Save handle | ハンドルを保存 |  |

### login.lisp（10件）
| key | en | ja | ⚑ |
|---|---|---|---|
| login.page_title | recurya - Sign in | recurya - ログイン |  |
| login.heading | Sign in to recurya | recurya にログイン |  |
| login.dev_stub.title | Dev OAuth stub is active. | 開発用 OAuth スタブが有効です。 | ⚑ |
| login.dev_stub.reuse_prefix |  Sign-in with any provider will create or reuse  | どのプロバイダでログインしても、Google や GitHub に接続せずに  | ⚑ |
| login.dev_stub.reuse_suffix |  without contacting Google or GitHub. |  を作成または再利用します。 | ⚑ |
| login.welcome | Welcome | ようこそ |  |
| login.help | Pick a provider to sign in. Your progress and saved code will follow you across devices. | ログインするプロバイダを選んでください。学習の進捗や保存したコードは、どの端末でも引き継がれます。 |  |
| login.button.google | Sign in with Google | Google でログイン |  |
| login.button.github | Sign in with GitHub | GitHub でログイン |  |
| login.footnote | We never see your password. Email and display name come from the provider you choose. | パスワードを当方が知ることはありません。メールアドレスと表示名は、選択したプロバイダから取得されます。 |  |

### course-list.lisp（9件）
*reused common:* common.pagination.info, common.pagination.prev, common.pagination.next

| key | en | ja | ⚑ |
|---|---|---|---|
| course_list.page_title | Courses | コース |  |
| course_list.heading | Courses | コース |  |
| course_list.subtitle | Community-authored Lisp courses. | コミュニティが作成した Lisp コース。 |  |
| course_list.card_meta | ~@[~A~]~@[ · ~A notebook~:P~]~@[ · ~A~] | ~@[~A~]~@[ · ~Aノートブック~]~@[ · ~A~] | ⚑ |
| common.pagination.info | Page ~A of ~A | ~A / ~A ページ |  |
| common.pagination.prev | ← Previous | ← 前へ |  |
| common.pagination.next | Next → | 次へ → |  |
| course_list.open_link | Open → | 開く → |  |
| course_list.empty | No courses yet. Check back soon! | まだコースがありません。またご確認ください。 |  |

### wardlisp-home.lisp（9件）
| key | en | ja | ⚑ |
|---|---|---|---|
| wardlisp.home.page_title | WardLisp - Puzzles | WardLisp - パズル |  |
| wardlisp.home.heading | WardLisp Puzzles | WardLisp パズル |  |
| wardlisp.home.subtitle | Learn Lisp by solving puzzles | パズルを解いてLispを学ぼう |  |
| wardlisp.home.difficulty_easy | Easy | やさしい |  |
| wardlisp.home.difficulty_medium | Medium | ふつう |  |
| wardlisp.home.difficulty_hard | Hard | むずかしい |  |
| wardlisp.home.nav_bot_arena | Bot Arena | ボットアリーナ | ⚑ |
| wardlisp.home.nav_playground | Playground | プレイグラウンド | ⚑ |
| wardlisp.home.nav_language_reference | Language Reference | 言語リファレンス |  |

### errors.lisp（8件）
| key | en | ja | ⚑ |
|---|---|---|---|
| errors.not_found.title | 404 - Not Found | 404 - ページが見つかりません |  |
| errors.not_found.body | The page you're looking for doesn't exist. | お探しのページは存在しません。 |  |
| errors.actions.go_to_dashboard | Go to Dashboard | ダッシュボードへ |  |
| errors.server_error.title | 500 - Server Error | 500 - サーバーエラー |  |
| errors.server_error.body | Something went wrong on our end. | サーバー側で問題が発生しました。 |  |
| errors.csrf.title | 400 - Invalid request | 400 - 無効なリクエスト |  |
| errors.csrf.body | Your session has expired or the request is invalid. Please go back to the previous page using your browser's back button, reload it, and try again. | セッションの有効期限が切れたか、リクエストが無効です。ブラウザの戻るボタンで前のページに戻り、再読み込みしてから再操作してください。 |  |
| errors.actions.home | Home | ホーム |  |

### notebook-list.lisp（8件）
*reused common:* common.pagination.info, common.pagination.prev, common.pagination.next

| key | en | ja | ⚑ |
|---|---|---|---|
| notebook_list.page_title | Notebooks | ノートブック |  |
| notebook_list.heading | Notebooks | ノートブック |  |
| notebook_list.subtitle | Community-authored Lisp notebooks. | コミュニティによって作成されたLispノートブック。 |  |
| notebook_list.open_link | Open → | 開く → |  |
| notebook_list.empty | No notebooks yet. Check back soon! | まだノートブックがありません。また後で確認してください。 |  |
| common.pagination.info | Page ~A of ~A | ~A / ~A ページ |  |
| common.pagination.prev | ← Previous | ← 前へ |  |
| common.pagination.next | Next → | 次へ → |  |

### playground.lisp（8件）
*reused common:* common.buttons.run

| key | en | ja | ⚑ |
|---|---|---|---|
| wardlisp.playground.page_title | WardLisp Playground | WardLisp プレイグラウンド |  |
| wardlisp.playground.breadcrumb_playground |  / Playground |  / プレイグラウンド |  |
| wardlisp.playground.heading | Playground | プレイグラウンド |  |
| wardlisp.playground.description | Write and run any WardLisp code. Experiment freely! | WardLisp のコードを自由に書いて実行できます。気軽に試してみましょう！ |  |
| wardlisp.playground.editor_placeholder | Write WardLisp code here... | ここに WardLisp のコードを書いてください... |  |
| common.buttons.run | Run | 実行 |  |
| wardlisp.playground.print_output_label | Print Output | 出力 | ⚑ |
| wardlisp.playground.metrics | Fuel: ~D \| Cons: ~D \| Depth: ~D | Fuel: ~D \| Cons: ~D \| Depth: ~D | ⚑ |

### course.lisp（7件）
| key | en | ja | ⚑ |
|---|---|---|---|
| course.draft_banner | Draft preview — only visible to the course owner. | 下書きプレビュー — コースの所有者のみに表示されます。 |  |
| course.page_title_fallback | Course | コース |  |
| course.untitled | Untitled course | 無題のコース |  |
| course.empty_notebooks | No notebooks attached to this course yet. | このコースにはまだノートブックが登録されていません。 |  |
| course.notebook_index | Notebook ~A | ノートブック ~A |  |
| course.passed_count | ~A passed | ~A 問正解 | ⚑ |
| course.open_notebook | Open notebook → | ノートブックを開く → |  |

### profile.lisp（4件）
| key | en | ja | ⚑ |
|---|---|---|---|
| profile.section.notebooks | Notebooks | ノートブック |  |
| profile.notebooks.empty | No public notebooks yet. | 公開中のノートブックはまだありません。 |  |
| profile.section.courses | Courses | コース |  |
| profile.courses.empty | No public courses yet. | 公開中のコースはまだありません。 |  |

### routes-wardlisp.lisp（2件）
| key | en | ja | ⚑ |
|---|---|---|---|
| wardlisp.puzzle.not_found_page | <h1>Puzzle not found</h1> | <h1>パズルが見つかりません</h1> |  |
| wardlisp.puzzle.not_found_fragment | <div class="error">Puzzle not found</div> | <div class="error">パズルが見つかりません</div> |  |

### novel.lisp（1件）
| key | en | ja | ⚑ |
|---|---|---|---|
| novel.end | — The End — | — おわり — |  |
