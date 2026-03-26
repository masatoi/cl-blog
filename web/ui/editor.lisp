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
           #:editor-textarea))

(in-package #:recurya/web/ui/editor)

(defparameter *importmap*
  "{
  \"imports\": {
    \"@codemirror/view\": \"https://esm.sh/@codemirror/view@6.36.5\",
    \"@codemirror/state\": \"https://esm.sh/@codemirror/state@6.5.2\",
    \"@codemirror/basic-setup\": \"https://esm.sh/@codemirror/basic-setup@0.20.0?external=@codemirror/view,@codemirror/state\",
    \"@codemirror/language\": \"https://esm.sh/@codemirror/language@6.10.8?external=@codemirror/view,@codemirror/state\",
    \"@codemirror/legacy-modes/mode/scheme\": \"https://esm.sh/@codemirror/legacy-modes@6.5.1/mode/scheme?external=@codemirror/language\",
    \"@codemirror/theme-one-dark\": \"https://esm.sh/@codemirror/theme-one-dark@6.1.2?external=@codemirror/view,@codemirror/state\"
  }
}"
  "Import map JSON pinning CodeMirror 6 packages to esm.sh CDN URLs.")

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
  padding: 0.5rem 0;
  caret-color: #38bdf8;
}"
  "CSS overrides for CodeMirror to match the site dark theme.")

(defun editor-head-tags ()
  "Return HTML string with importmap and style tags for CodeMirror 6.

Include this in the <head> of any page that uses the editor component."
  (with-html-string
    (:script :type "importmap" (:raw *importmap*))
    (:style (:raw *editor-styles*))))

(defun editor-textarea (name initial-value &key (placeholder ""))
  "Return HTML string with a hidden textarea, CodeMirror mount div, and init script.

NAME is the form field name for the hidden textarea.
INITIAL-VALUE is the starting content of the editor.
PLACEHOLDER, when non-empty, sets an aria-placeholder attribute on the editor."
  (let ((escaped-value (escape-string initial-value))
        (escaped-placeholder (escape-string placeholder))
        (has-placeholder (and placeholder (stringp placeholder)
                             (> (length placeholder) 0))))
    (with-html-string
      ;; Hidden textarea for form submission
      (:textarea :id "editor-source"
                 :name name
                 :style "display:none"
                 (:raw escaped-value))
      ;; CodeMirror mount point
      (:div :id "editor-mount")
      ;; Initialization script
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

  const textarea = document.getElementById('editor-source');
  const mount = document.getElementById('editor-mount');

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
} catch (e) {
  console.error('CodeMirror failed to load:', e);
  const textarea = document.getElementById('editor-source');
  const mount = document.getElementById('editor-mount');
  textarea.style.display = '';
  mount.style.display = 'none';
}
"
          (if has-placeholder
              (format nil ",~%    EditorView.contentAttributes.of({\"aria-placeholder\": \"~A\"})"
                      escaped-placeholder)
              "")))))))
