# CodeMirror 6 Editor Integration Design

## Goal

Replace raw `<textarea>` elements in puzzle and arena pages with CodeMirror 6 editors providing bracket matching, auto-indentation, and syntax highlighting for WardLisp code.

## Architecture

CDN-loaded (esm.sh) CodeMirror 6 with Scheme language mode. A shared component `web/ui/editor.lisp` provides head tags and editor initialization, called from both puzzle and arena pages. Hidden `<textarea>` syncs editor content for HTMX form submission.

## Scope

### In Scope
- Bracket matching (highlight matching parentheses)
- Auto-indentation (Lisp-style)
- Syntax highlighting (Scheme mode — covers `define`, `lambda`, `if`, `let`, `cond`, `quote`, etc.)
- Dark theme (oneDark, matches existing site UI)

### Out of Scope
- Custom WardLisp-specific language mode
- Auto-close brackets
- Line numbers (included in basicSetup but acceptable)
- Offline/self-hosted assets

## Data Flow

```
Page load
  → <textarea name="code" id="editor-source" style="display:none"> (hidden)
  → CodeMirror initializes from textarea content
  → User edits code in CodeMirror
  → updateListener → syncs to hidden textarea
  → HTMX button → hx-include "closest form" → POSTs textarea.value
```

HTMX compatibility: CodeMirror creates its own DOM, so the original `<textarea>` is hidden and kept in sync via `EditorView.updateListener`. This preserves existing `hx-include` form submission.

## CDN Dependencies

All loaded via esm.sh as ES modules:

| Package | Purpose |
|---------|---------|
| `@codemirror/basic-setup` | Core setup: bracket matching, indentation, etc. |
| `@codemirror/language` | `StreamLanguage` for legacy mode integration |
| `@codemirror/legacy-modes/mode/scheme` | Scheme syntax highlighting |
| `@codemirror/theme-one-dark` | Dark theme matching site design |

## File Changes

| File | Change |
|------|--------|
| **Create** `web/ui/editor.lisp` | Shared component: CDN script tags, editor init JS, dark theme CSS overrides |
| **Modify** `web/ui/puzzle.lisp` | Replace textarea with editor component calls, remove textarea CSS |
| **Modify** `web/ui/arena.lisp` | Same as puzzle |
| **Modify** `recurya.asd` | Add `recurya/web/ui/editor` to depends-on |

## editor.lisp Public API

### `(editor-head-tags)`
Outputs `<script type="importmap">` or inline module script in `<head>` for CDN imports.

### `(editor-textarea name initial-value &key placeholder)`
Outputs:
1. Hidden `<textarea name=NAME id="editor-source">INITIAL-VALUE</textarea>`
2. `<div id="editor-mount"></div>` — CodeMirror mount point
3. `<script type="module">` — initializes CodeMirror, wires updateListener

## Server-Side Impact

None. Route handlers continue to read the `code` parameter from POST body. No changes to `web/routes-wardlisp.lisp` or any backend logic.

## Risks

- **CDN availability**: If esm.sh is down, editor won't load. Fallback: the hidden textarea becomes visible via `<noscript>` or JS error handler, allowing basic editing.
- **esm.sh module resolution**: Pinning specific versions avoids breaking changes.
- **Multiple editors on one page**: Current design assumes one editor per page (matches current usage).
