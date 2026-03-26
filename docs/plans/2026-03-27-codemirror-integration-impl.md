# CodeMirror 6 Editor Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace raw `<textarea>` elements in puzzle and arena pages with CodeMirror 6 editors providing bracket matching, auto-indentation, and syntax highlighting for WardLisp code.

**Architecture:** CDN-loaded (esm.sh) CodeMirror 6 with Scheme language mode. A shared Spinneret component `web/ui/editor.lisp` provides importmap tags and editor initialization JS. Hidden `<textarea>` syncs editor content for HTMX form submission via `updateListener`.

**Tech Stack:** CodeMirror 6 (via esm.sh CDN), Scheme legacy mode, oneDark theme, Spinneret HTML generation, HTMX

---

### Task 1: Create shared editor component (`web/ui/editor.lisp`)

**Files:**
- Create: `web/ui/editor.lisp`

**Step 1: Create the editor component file**

Write `web/ui/editor.lisp` with the following content:

```lisp
;;;; web/ui/editor.lisp --- CodeMirror 6 editor component for WardLisp code editing.

(defpackage #:recurya/web/ui/editor
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string)
  (:export #:editor-head-tags
           #:editor-textarea))

(in-package #:recurya/web/ui/editor)

(defparameter *codemirror-version* "6.36.5"
  "Pinned CodeMirror view version for CDN loading.")

(defun editor-head-tags ()
  "Output <script type=\"importmap\"> and CSS overrides for CodeMirror in <head>.
   Must be called inside a Spinneret (:head ...) form."
  (with-html-string
    ;; Importmap pins all CodeMirror packages to compatible versions via esm.sh
    (:script :type "importmap"
     (:raw
      (format nil "{
  \"imports\": {
    \"@codemirror/view\": \"https://esm.sh/@codemirror/view@~A\",
    \"@codemirror/state\": \"https://esm.sh/@codemirror/state@6.5.2\",
    \"@codemirror/basic-setup\": \"https://esm.sh/@codemirror/basic-setup@0.20.0?external=@codemirror/view,@codemirror/state\",
    \"@codemirror/language\": \"https://esm.sh/@codemirror/language@6.10.8?external=@codemirror/view,@codemirror/state\",
    \"@codemirror/legacy-modes/mode/scheme\": \"https://esm.sh/@codemirror/legacy-modes@6.5.1/mode/scheme?external=@codemirror/language\",
    \"@codemirror/theme-one-dark\": \"https://esm.sh/@codemirror/theme-one-dark@6.1.2?external=@codemirror/view,@codemirror/state\"
  }
}" *codemirror-version*)))
    ;; CSS overrides to match site dark theme
    (:style (:raw
     ".cm-editor { background: #1e293b; border: 1px solid #334155; border-radius: 8px;
                   font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.95rem;
                   min-height: 180px; }
      .cm-editor.cm-focused { outline: 2px solid #38bdf8; border-color: #38bdf8; }
      .cm-scroller { overflow: auto; padding: 0.5rem 0; }
      .cm-content { padding: 0 0.5rem; }"))))

(defun editor-textarea (name initial-value &key (placeholder ""))
  "Output a hidden textarea, CodeMirror mount div, and initialization script.
   NAME is the form field name (e.g. \"code\").
   INITIAL-VALUE is the default code string.
   PLACEHOLDER is shown when editor is empty."
  (with-html-string
    ;; Hidden textarea for HTMX form submission
    (:textarea :id "editor-source" :name name
               :style "display:none"
               initial-value)
    ;; CodeMirror mount point
    (:div :id "editor-mount")
    ;; Initialization script
    (:script :type "module"
     (:raw
      (format nil "
import {EditorView, keymap} from '@codemirror/view';
import {EditorState} from '@codemirror/state';
import {basicSetup} from '@codemirror/basic-setup';
import {StreamLanguage} from '@codemirror/language';
import {scheme} from '@codemirror/legacy-modes/mode/scheme';
import {oneDark} from '@codemirror/theme-one-dark';

const textarea = document.getElementById('editor-source');
const mount = document.getElementById('editor-mount');

const updateListener = EditorView.updateListener.of(update => {
  if (update.docChanged) {
    textarea.value = update.state.doc.toString();
  }
});

const editor = new EditorView({
  state: EditorState.create({
    doc: textarea.value,
    extensions: [
      basicSetup,
      StreamLanguage.define(scheme),
      oneDark,
      updateListener,
      EditorView.theme({
        '&': {minHeight: '180px'},
        '.cm-content': {fontFamily: \"'SF Mono', 'Fira Code', monospace\"}
      }),
      ~A
    ]
  }),
  parent: mount
});

// Fallback: if module loading fails, show the textarea
window.addEventListener('error', function(e) {
  if (mount && !mount.querySelector('.cm-editor')) {
    textarea.style.display = '';
    mount.style.display = 'none';
  }
}, true);
" (if (string= placeholder "")
      "[]"
      (format nil "EditorView.contentAttributes.of({\"aria-placeholder\": ~S})" placeholder)))))))
```

**Step 2: Verify parentheses are balanced**

Use `lisp-check-parens` on the new file to verify no syntax errors.

**Step 3: Load and verify the component compiles**

```lisp
(asdf:load-system "recurya/web/ui/editor" :force t)
```

Verify no compilation warnings or errors.

**Step 4: Test the functions produce valid HTML**

```lisp
(recurya/web/ui/editor:editor-head-tags)
;; Should return HTML string with <script type="importmap"> and <style>

(recurya/web/ui/editor:editor-textarea "code" "(define (add a b) (+ a b))" :placeholder "Write code...")
;; Should return HTML string with hidden textarea, mount div, and module script
```

**Step 5: Commit**

```bash
git add web/ui/editor.lisp
git commit -m "feat: add shared CodeMirror 6 editor component"
```

---

### Task 2: Register editor component in ASDF system

**Files:**
- Modify: `recurya.asd` (add `"recurya/web/ui/editor"` before `"recurya/web/ui/puzzle"`)

**Step 1: Add the new module to recurya.asd**

In `recurya.asd`, in the `depends-on` list, add `"recurya/web/ui/editor"` immediately before `"recurya/web/ui/puzzle"` (around line 64):

```lisp
               ;; WardLisp UI
               "recurya/web/ui/wardlisp-home"
               "recurya/web/ui/editor"
               "recurya/web/ui/puzzle"
```

**Step 2: Verify the system loads**

```lisp
(asdf:load-system "recurya" :force t)
```

No errors expected.

**Step 3: Commit**

```bash
git add recurya.asd
git commit -m "feat: register editor component in ASDF system"
```

---

### Task 3: Integrate editor into puzzle page

**Files:**
- Modify: `web/ui/puzzle.lisp`

**Step 1: Add import for editor component**

Add `:import-from` for `recurya/web/ui/editor` in the package definition:

```lisp
  (:import-from #:recurya/web/ui/editor
                #:editor-head-tags
                #:editor-textarea)
```

**Step 2: Add editor head tags to the `<head>` section**

In the `render` function, after the `(:style (:raw *styles*))` line (line 92), add:

```lisp
        (:raw (editor-head-tags))
```

**Step 3: Replace textarea with editor-textarea call**

In the `render` function, replace the existing textarea (lines 110-113):

```lisp
          (:textarea :name "code" :placeholder "Write your solution here..."
                     :autofocus t
                     :spellcheck "false"
                     (format nil "; ~A~%~%" (puzzle-signature puzzle)))
```

With:

```lisp
          (:raw (editor-textarea "code"
                                 (format nil "; ~A~%~%" (puzzle-signature puzzle))
                                 :placeholder "Write your solution here..."))
```

**Step 4: Remove textarea CSS from `*styles*`**

Remove these CSS rules from `*styles*` (lines 51-55) since CodeMirror handles its own styling:

```css
.editor-area textarea { width: 100%; min-height: 200px; font-family: 'SF Mono', 'Fira Code', monospace;
                        font-size: 0.95rem; background: #1e293b; color: #e2e8f0;
                        border: 1px solid #334155; border-radius: 8px; padding: 1rem;
                        resize: vertical; line-height: 1.5; tab-size: 2; }
.editor-area textarea:focus { outline: 2px solid #38bdf8; border-color: #38bdf8; }
```

**Step 5: Verify compilation**

```lisp
(asdf:load-system "recurya/web/ui/puzzle" :force t)
```

**Step 6: Test render produces editor HTML**

```lisp
;; Create a test puzzle and verify render output contains CodeMirror elements
(let ((html (recurya/web/ui/puzzle:render <test-puzzle>)))
  (assert (search "importmap" html))
  (assert (search "editor-mount" html))
  (assert (search "editor-source" html))
  (assert (null (search "autofocus" html))))  ;; old textarea attrs removed
```

**Step 7: Commit**

```bash
git add web/ui/puzzle.lisp
git commit -m "feat: integrate CodeMirror editor into puzzle page"
```

---

### Task 4: Integrate editor into arena page

**Files:**
- Modify: `web/ui/arena.lisp`

**Step 1: Add import for editor component**

Add `:import-from` for `recurya/web/ui/editor` in the package definition:

```lisp
  (:import-from #:recurya/web/ui/editor
                #:editor-head-tags
                #:editor-textarea)
```

**Step 2: Add editor head tags to the `<head>` section**

In the `render` function, after the `(:style (:raw *styles*))` line (line 122), add:

```lisp
        (:raw (editor-head-tags))
```

**Step 3: Replace textarea with editor-textarea call**

In the `render` function, replace the existing textarea (lines 133-139):

```lisp
        (:textarea :name "code" :placeholder "Write your decide-action function..."
                   :autofocus t :spellcheck "false"
                   "(define (decide-action state)
  ; state is an alist with keys:
  ;   my-pos, enemy-pos, my-score, enemy-score, turn, max-turns
  ; Return: 'up, 'down, 'left, 'right, 'wait, or 'pickup
  'right)")
```

With:

```lisp
        (:raw (editor-textarea "code"
                               "(define (decide-action state)
  ; state is an alist with keys:
  ;   my-pos, enemy-pos, my-score, enemy-score, turn, max-turns
  ; Return: 'up, 'down, 'left, 'right, 'wait, or 'pickup
  'right)"
                               :placeholder "Write your decide-action function..."))
```

**Step 4: Remove textarea CSS from `*styles*`**

Remove these CSS rules from `*styles*` (lines 35-39):

```css
.editor-area textarea { width: 100%; min-height: 180px; font-family: 'SF Mono', 'Fira Code', monospace;
                        font-size: 0.95rem; background: #1e293b; color: #e2e8f0;
                        border: 1px solid #334155; border-radius: 8px; padding: 1rem;
                        resize: vertical; line-height: 1.5; tab-size: 2; }
.editor-area textarea:focus { outline: 2px solid #38bdf8; border-color: #38bdf8; }
```

**Step 5: Verify compilation**

```lisp
(asdf:load-system "recurya/web/ui/arena" :force t)
```

**Step 6: Test render produces editor HTML**

```lisp
(let ((html (recurya/web/ui/arena:render)))
  (assert (search "importmap" html))
  (assert (search "editor-mount" html))
  (assert (search "editor-source" html))
  (assert (null (search "autofocus" html))))
```

**Step 7: Commit**

```bash
git add web/ui/arena.lisp
git commit -m "feat: integrate CodeMirror editor into arena page"
```

---

### Task 5: Manual browser verification

**Step 1: Reload the full system**

```lisp
(asdf:load-system "recurya" :force t)
```

Or restart the container if needed.

**Step 2: Verify puzzle page**

Open `http://localhost:3000/wardlisp/puzzle/adjacent` in a browser. Verify:
- CodeMirror editor loads (not a plain textarea)
- Syntax highlighting is active (Scheme mode colors)
- Bracket matching works (click next to a paren)
- Auto-indentation works (press Enter after opening paren)
- Dark theme (oneDark) matches site background
- "Run" button submits code and shows results

**Step 3: Verify arena page**

Open `http://localhost:3000/wardlisp/arena` in a browser. Verify:
- CodeMirror editor loads with default bot code
- Same features as puzzle page
- "Run Simulation" button works and shows arena result

**Step 4: Verify fallback**

Open browser DevTools, block `esm.sh` domain in Network tab. Reload page. Verify:
- Hidden textarea becomes visible (fallback)
- Form submission still works with plain textarea

**Step 5: Final commit (if any CSS tweaks needed)**

```bash
git add -A
git commit -m "fix: adjust editor styling after browser testing"
```
