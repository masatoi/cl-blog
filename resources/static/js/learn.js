// resources/static/js/learn.js
// Progress tracking for SICP notebook course.
// Anonymous: localStorage. Logged-in: server (this script syncs once on login).

const STORAGE_KEY = 'recurya:learn:v1';

function isLoggedIn() {
  return document.body.dataset.loggedIn === 'true';
}

function loadProgress() {
  try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {}; }
  catch (_) { return {}; }
}

function saveProgress(obj) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(obj));
}

function ensureNotebookEntry(progress, notebookId) {
  if (!progress[notebookId]) {
    progress[notebookId] = { passed: [], codes: {}, last_visited_at: null };
  }
  if (!progress[notebookId].codes) progress[notebookId].codes = {};
  if (!progress[notebookId].passed) progress[notebookId].passed = [];
  return progress[notebookId];
}

function recordPass(notebookId, cellId) {
  const p = loadProgress();
  const entry = ensureNotebookEntry(p, notebookId);
  if (!entry.passed.includes(cellId)) entry.passed.push(cellId);
  entry.last_visited_at = new Date().toISOString();
  saveProgress(p);
}

function recordCode(notebookId, cellId, code) {
  const p = loadProgress();
  const entry = ensureNotebookEntry(p, notebookId);
  entry.codes[cellId] = code;
  entry.last_visited_at = new Date().toISOString();
  saveProgress(p);
}

function badge(text) {
  const b = document.createElement('span');
  b.className = 'progress-badge';
  b.textContent = text;
  b.style.cssText =
    'float:right;background:#16a34a;color:#fff;' +
    'padding:2px 8px;border-radius:999px;font-size:0.75rem;';
  return b;
}

function markCellBadge(cellNode) {
  if (!cellNode || cellNode.querySelector('.progress-badge')) return;
  cellNode.prepend(badge('✓ done'));
}

function markCompletedCells(notebookId) {
  const nb = loadProgress()[notebookId];
  if (!nb) return;
  for (const cellId of nb.passed || []) {
    const cell = document.querySelector(
      `[data-cell-id="${CSS.escape(cellId.toLowerCase())}"]`);
    markCellBadge(cell);
  }
}

function renderHomeCardProgress() {
  const progress = loadProgress();
  document.querySelectorAll('[data-notebook-id]').forEach((card) => {
    const nbId = card.dataset.notebookId;
    const nbProgress = progress[nbId];
    if (!nbProgress || !nbProgress.passed || nbProgress.passed.length === 0) return;
    const meta = card.querySelector('.nb-card__meta');
    if (meta) {
      const tag = document.createElement('span');
      tag.textContent = ` · ${nbProgress.passed.length} 完了`;
      tag.style.color = '#4ade80';
      meta.appendChild(tag);
    }
  });
}

async function maybeSyncLocalProgress() {
  if (!isLoggedIn()) return;
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return;
  let payload;
  try { payload = JSON.parse(raw); } catch (_) { return; }
  const notebooks = Object.entries(payload).map(([nbId, val]) => ({
    notebook_id: nbId,
    passed: val.passed || [],
    codes: val.codes || {},
  }));
  if (notebooks.length === 0) return;
  try {
    const res = await fetch('/wardlisp/learn/sync', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({notebooks}),
    });
    if (res.ok) {
      localStorage.removeItem(STORAGE_KEY);
    }
  } catch (_) {
    // Network error — keep localStorage intact for retry on next load.
  }
}

// --- Read-only CodeMirror for solution code (syntax highlighting, no edit).
// Progressive enhancement: the server renders the solution as a <pre>
// (.cm-readonly-src) inside a .cm-readonly container; upgrade it in place to a
// read-only CodeMirror matching the editor. Works inside <details> (re-measures
// on open) and for HTMX out-of-band reveals (re-scanned on htmx swaps).
async function mountReadonlyEditor(container) {
  const src = container.querySelector('.cm-readonly-src');
  const mount = container.querySelector('.cm-readonly-mount');
  if (!src || !mount) return;
  const code = src.textContent;
  try {
    const [{ EditorView }, { EditorState }, { basicSetup },
           { StreamLanguage }, { scheme }, { oneDark }] = await Promise.all([
      import('@codemirror/view'),
      import('@codemirror/state'),
      import('@codemirror/basic-setup'),
      import('@codemirror/language'),
      import('@codemirror/legacy-modes/mode/scheme'),
      import('@codemirror/theme-one-dark'),
    ]);
    const view = new EditorView({
      state: EditorState.create({
        doc: code,
        extensions: [
          basicSetup,
          StreamLanguage.define(scheme),
          oneDark,
          EditorState.readOnly.of(true),
          EditorView.editable.of(false),
        ],
      }),
      parent: mount,
    });
    src.style.display = 'none'; // hide the fallback <pre>
    const details = container.closest('details');
    if (details) {
      details.addEventListener('toggle', () => {
        if (details.open) view.requestMeasure();
      });
      if (details.open) view.requestMeasure();
    } else {
      view.requestMeasure();
    }
  } catch (e) {
    console.error('read-only CodeMirror failed to load:', e);
    // Leave the fallback <pre> visible.
  }
}

function initReadonlyEditors(root) {
  (root || document).querySelectorAll('.cm-readonly:not([data-cm-init])')
    .forEach((c) => { c.setAttribute('data-cm-init', '1'); mountReadonlyEditor(c); });
}

document.addEventListener('DOMContentLoaded', () => {
  initReadonlyEditors(document);
  if (isLoggedIn()) {
    // Logged-in: server provides SSR badges; sync any leftover local data.
    maybeSyncLocalProgress();
    return;
  }
  // Anonymous: read localStorage and decorate.
  const nbId = document.body.dataset.notebookId;
  if (nbId && document.body.dataset.page !== 'learn-home') {
    markCompletedCells(nbId);
  }
  if (document.body.dataset.page === 'learn-home') {
    renderHomeCardProgress();
  }
});

document.body.addEventListener('cell-passed', (e) => {
  // Logged-in: server already saved this; SSR badge will appear on next load.
  // For both modes, surface the badge immediately for snappy UX.
  const detail = (e && e.detail) || {};
  const nb = detail.notebook;
  const cell = detail.cell;
  if (!nb || !cell) return;
  if (!isLoggedIn()) recordPass(nb, cell);
  const node = document.querySelector(
    `[data-cell-id="${CSS.escape(cell.toLowerCase())}"]`);
  markCellBadge(node);
});

// Reset button: restore the cell's textarea + CodeMirror view to the
// notebook's original code (data-original-code on the cell wrapper).
document.body.addEventListener('click', (e) => {
  const btn = e.target.closest('.btn-reset');
  if (!btn) return;
  const cell = btn.closest('[data-cell-id]');
  if (!cell) return;
  const original = cell.dataset.originalCode || '';
  const textareaId = cell.dataset.textareaId;
  if (!textareaId) return;
  const ta = document.getElementById(textareaId);
  if (ta) ta.value = original;
  const view = (window.cmEditors || {})[textareaId];
  if (view) {
    view.dispatch({
      changes: {from: 0, to: view.state.doc.length, insert: original}
    });
  }
});

// Capture textarea value into localStorage (anonymous only) on every Run.
document.body.addEventListener('htmx:afterRequest', (e) => {
  if (isLoggedIn()) return; // server saves logged-in cell code
  const url = (e.detail && e.detail.requestConfig && e.detail.requestConfig.path) || '';
  const m = url.match(/\/wardlisp\/learn\/([^\/]+)\/cells\/(\d+)\/run/);
  if (!m) return;
  const nbId = m[1];
  const cellIdx = parseInt(m[2], 10);
  // Per-cell textareas are class="notebook-code" in DOM order.
  const tas = document.querySelectorAll('textarea.notebook-code');
  const ta = tas[cellIdx];
  if (!ta) return;
  const cellId = ta.closest('[data-cell-id]')?.dataset?.cellId;
  if (!cellId) return;
  recordCode(nbId, cellId, ta.value);
});

// Upgrade read-only solution editors after HTMX swaps, including out-of-band
// gated-solution reveals. Idempotent via the data-cm-init marker.
['htmx:load', 'htmx:afterSwap', 'htmx:oobAfterSwap'].forEach((evt) => {
  document.body.addEventListener(evt, () => initReadonlyEditors(document));
});
