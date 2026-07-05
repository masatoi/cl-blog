;;;; web/ui/editor.lisp --- Shared CodeMirror 6 editor component.
;;;;
;;;; Provides two functions for embedding a CodeMirror 6 code editor:
;;;; - editor-head-tags: returns <script type="importmap"> and <style> tags
;;;; - editor-textarea: returns a hidden textarea + CodeMirror mount point + init script
;;;;
;;;; CodeMirror packages are loaded from esm.sh CDN with pinned versions.

(defpackage #:recurya/web/ui/editor
  (:use #:cl)
  (:import-from #:spinneret
                #:with-html-string
                #:escape-string)
  (:export #:editor-head-tags
           #:editor-textarea
           #:editor-readonly))

(in-package #:recurya/web/ui/editor)

(defparameter *importmap*
  "{
  \"imports\": {
    \"@lezer/highlight\": \"https://esm.sh/*@lezer/highlight@1.2.1\",
    \"@codemirror/state\": \"https://esm.sh/*@codemirror/state@6.5.2\",
    \"@codemirror/view\": \"https://esm.sh/*@codemirror/view@6.36.5\",
    \"@codemirror/language\": \"https://esm.sh/*@codemirror/language@6.10.8\",
    \"@codemirror/commands\": \"https://esm.sh/*@codemirror/commands@6.8.1\",
    \"@codemirror/search\": \"https://esm.sh/*@codemirror/search@6.5.10\",
    \"@codemirror/autocomplete\": \"https://esm.sh/*@codemirror/autocomplete@6.18.6\",
    \"@codemirror/lint\": \"https://esm.sh/*@codemirror/lint@6.8.5\",
    \"@codemirror/basic-setup\": \"https://esm.sh/*@codemirror/basic-setup@0.20.0\",
    \"@codemirror/legacy-modes/mode/scheme\": \"https://esm.sh/*@codemirror/legacy-modes@6.5.1/mode/scheme\",
    \"@codemirror/theme-one-dark\": \"https://esm.sh/*@codemirror/theme-one-dark@6.1.2\",
    \"style-mod\": \"https://esm.sh/*style-mod@4.1.2\",
    \"w3c-keyname\": \"https://esm.sh/*w3c-keyname@2.2.8\",
    \"@marijn/find-cluster-break\": \"https://esm.sh/*@marijn/find-cluster-break@1.0.2\",
    \"@lezer/common\": \"https://esm.sh/*@lezer/common@1.2.3\",
    \"crelt\": \"https://esm.sh/*crelt@1.0.6\"
  }
}"
  "Import map JSON pinning CodeMirror 6 packages to esm.sh CDN with bundle mode (*).")

(defparameter *editor-styles*
  ".cm-editor {
  background: #1e293b;
  border: 1px solid #334155;
  border-radius: 8px;
  font-family: 'SF Mono', 'Fira Code', monospace;
  font-size: 0.95rem;
  min-height: 200px;
}
.cm-editor.cm-focused {
  outline: 2px solid #38bdf8;
  border-color: #38bdf8;
}
.cm-scroller {
  overflow: auto;
  padding: 0.5rem 0;
}
.cm-content {
  padding: 0 0.5rem;
  caret-color: #38bdf8;
}
.cm-cursor, .cm-dropCursor {
  border-left-width: 0.55em !important;
  border-color: rgba(56, 189, 248, 0.7) !important;
}
.cm-readonly .cm-editor { min-height: auto; }
.cm-readonly .cm-cursor { display: none !important; }"
  "CSS overrides for CodeMirror to match the site dark theme.")

(defun editor-head-tags ()
  "Return HTML string with importmap and style tags for CodeMirror 6.

Include this in the <head> of any page that uses the editor component.
Uses esm.sh bundle mode (*) so each package is self-contained."
  (with-html-string
    (:script :type "importmap" (:raw *importmap*))
    (:style (:raw *editor-styles*))))

(defun editor-textarea (name initial-value &key (placeholder "")
                                                (id-suffix "")
                                                (textarea-class nil))
  "Return HTML string with a hidden textarea, CodeMirror mount div, and init script.

NAME is the form field name for the hidden textarea.
INITIAL-VALUE is the starting content of the editor.
PLACEHOLDER, when non-empty, sets an aria-placeholder attribute on the editor.
ID-SUFFIX disambiguates DOM ids when multiple editors appear on one page.
  Ids become 'editor-source<suffix>' and 'editor-mount<suffix>'; pass \"\"
  (the default) for single-editor pages to keep legacy ids.
TEXTAREA-CLASS, when non-nil, is set as the class attribute of the hidden
  textarea so HTMX hx-include selectors (e.g. '.notebook-code') can collect it.

Uses esm.sh bundle mode (*) for fast single-request loading."
  (let ((escaped-value (escape-string initial-value))
        (escaped-placeholder (escape-string placeholder))
        (has-placeholder
         (and placeholder (stringp placeholder) (> (length placeholder) 0)))
        (source-id (format nil "editor-source~A" id-suffix))
        (mount-id (format nil "editor-mount~A" id-suffix)))
    (with-html-string
      (if textarea-class
          (:textarea :id source-id :name name :class textarea-class
                     :style "display:none"
                     (:raw escaped-value))
          (:textarea :id source-id :name name :style "display:none"
                     (:raw escaped-value)))
      (:div :id mount-id)
      (:script :type "module"
       (:raw
        (format nil "
try {
  const { EditorView } = await import('@codemirror/view');
  const { EditorState } = await import('@codemirror/state');
  const { basicSetup } = await import('@codemirror/basic-setup');
  const { StreamLanguage } = await import('@codemirror/language');
  const { scheme } = await import('@codemirror/legacy-modes/mode/scheme');
  const { oneDark } = await import('@codemirror/theme-one-dark');

  const textarea = document.getElementById('~A');
  const mount = document.getElementById('~A');

  const extensions = [
    basicSetup,
    StreamLanguage.define(scheme),
    oneDark,
    EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        textarea.value = update.state.doc.toString();
      }
    })~A
  ];

  const view = new EditorView({
    state: EditorState.create({
      doc: textarea.value,
      extensions: extensions
    }),
    parent: mount
  });
  // Expose view for external controls (reset button etc.)
  window.cmEditors = window.cmEditors || {};
  window.cmEditors[textarea.id] = view;
} catch (e) {
  console.error('CodeMirror failed to load:', e);
  const textarea = document.getElementById('~A');
  const mount = document.getElementById('~A');
  textarea.style.display = '';
  mount.style.display = 'none';
}
"
          source-id
          mount-id
          (if has-placeholder
              (format nil ",~%    EditorView.contentAttributes.of({\"aria-placeholder\": \"~A\"})"
                      escaped-placeholder)
              "")
          source-id
          mount-id))))))

(defun editor-readonly (code)
  "Return HTML for a read-only, syntax-highlighted view of CODE.

Progressive enhancement: CODE is rendered inside a <pre> (the no-JS /
CM-load-failure fallback, styled like the plain solution body) within a
`.cm-readonly' container; learn.js upgrades it in place to a read-only
CodeMirror (Scheme + oneDark) matching the editor. Carries NO inline script,
so it works unchanged inside a collapsed <details> and inside HTMX
out-of-band swaps -- the initializer runs on DOMContentLoaded and on htmx
swaps, re-measuring when a <details> is opened."
  (with-html-string
    (:div :class "cm-readonly"
          (:pre :class "solution-body cm-readonly-src" code)
          (:div :class "cm-readonly-mount"))))
