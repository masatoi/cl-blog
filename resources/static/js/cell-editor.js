// cell-editor.js
//
// Pure serialization logic for the cell-based notebook editor.
//
// `cellsToBody` converts an array of server-shaped cell objects into the exact
// fence-format markdown string produced by the server's Lisp
// `cells->body-md` (see web/ui or notebook rendering code for the
// authoritative Lisp implementation). The cell objects consumed here are the
// canonical `data-cells` shape emitted by Lisp `cell->jsonb-form`, i.e. exactly
// what `JSON.parse(dataCells)` yields: kebab-case keys such as `test-cases`,
// and per-test-case `expected` (not `output`). This module is intentionally
// free of DOM access, CodeMirror imports, and top-level side effects so it can
// be imported and unit-tested under plain Node.js as well as loaded in the
// browser via `<script type="module">`.

/**
 * Render a single server-shaped test-case object to its fence-format text.
 *
 * @param {{description?: string, input?: string, expected?: string}} testCase
 * @returns {string}
 */
function renderTestCase(testCase) {
  const description = testCase.description ?? '';
  const input = testCase.input ?? '';
  const expected = testCase.expected ?? '';

  const header = description.length > 0
    ? `===expect: ${description}===`
    : '===expect===';

  const body = input.length > 0
    ? `input: ${input}\noutput: ${expected}`
    : `${expected}`;

  return `${header}\n${body}`;
}

/**
 * Render the header line for a cell, given its kind and (for a `code-solution`
 * cell) description. A `code-solution` cell with a truthy `gated` flag renders
 * the `===solution-locked:===` fence variant (a gated solution, hidden until
 * unlocked) instead of the plain `===solution:===`.
 *
 * Note: `code-exercise` cells are NOT built through this header — they use the
 * multi-line `===exercise===`/`===code===` block form, which `renderCell`
 * assembles directly (a description can itself span multiple lines/paragraphs
 * of Markdown, so it cannot be folded into a single `===exercise: ...===`
 * header line). The `code-exercise` case below is unreachable in practice but
 * kept as a defensive fallback.
 *
 * @param {{kind: string, description?: string, gated?: boolean}} cell
 * @returns {string}
 */
function renderCellHeader(cell) {
  const kind = cell.kind;
  const description = cell.description ?? '';
  switch (kind) {
    case 'prose':
      return '===prose===';
    case 'code-eval':
      return '===eval===';
    case 'scene':
      return '===scene===';
    case 'code-exercise':
      return `===exercise: ${description}===`;
    case 'code-solution': {
      // A solution header is a single line, so fold any newlines in the
      // description (e.g. carried over when a multi-line exercise is switched
      // to a solution) to spaces — otherwise the header would span lines and
      // fail to re-parse, silently dropping the cell.
      const oneLine = description.replace(/\n/g, ' ');
      return cell.gated
        ? `===solution-locked: ${oneLine}===`
        : `===solution: ${oneLine}===`;
    }
    default:
      throw new Error(`cellsToBody: unknown cell kind "${kind}"`);
  }
}

/**
 * Render a single server-shaped cell object to its fence-format text (no
 * leading/trailing cell separators). `code-exercise` cells render as the
 * `===exercise===\n<description>\n===code===\n<body>` block form (the
 * description may itself be multi-line Markdown), matching Lisp
 * `cells->body-md`; every other kind uses `renderCellHeader`'s single-line
 * header followed by the body.
 *
 * @param {{kind: string, body?: string, description?: string, "test-cases"?: Array, gated?: boolean}} cell
 * @returns {string}
 */
function renderCell(cell) {
  const body = cell.body ?? '';
  let rendered;
  if (cell.kind === 'code-exercise') {
    const description = cell.description ?? '';
    rendered = `===exercise===\n${description}\n===code===\n${body}`;
  } else {
    rendered = `${renderCellHeader(cell)}\n${body}`;
  }

  if (cell.kind === 'code-exercise') {
    // Tolerate the Lisp nil -> JSON `false` quirk for an empty test-case list
    // (see serverCellToState); a raw server cell can carry `false` here.
    const rawTestCases = cell['test-cases'];
    const testCases = Array.isArray(rawTestCases) ? rawTestCases : [];
    for (const testCase of testCases) {
      rendered += '\n\n' + renderTestCase(testCase);
    }
  }

  return rendered;
}

/**
 * Serialize an array of server-shaped cell objects (the `data-cells` shape
 * from Lisp `cell->jsonb-form`, as produced by `JSON.parse(dataCells)`) into
 * the fence-format markdown body string used by notebook lessons, matching the
 * Lisp `cells->body-md` byte-for-byte.
 *
 * @param {Array<{kind: string, body?: string, description?: string, "test-cases"?: Array, gated?: boolean}>} cells
 * @returns {string}
 */
export function cellsToBody(cells) {
  return cells.map(renderCell).join('\n\n');
}

// -----------------------------------------------------------------------
// Browser cell editor UI (CodeMirror-based).
//
// Everything below this point is browser-only: it reads/writes `document`,
// dynamically imports CodeMirror 6 packages (already wired up via the page's
// importmap, see `web/ui/editor.lisp`), and mutates the DOM. It is guarded
// behind `typeof document !== 'undefined'` at the very bottom of this file so
// that importing this module under plain Node.js (see
// `cell-editor.test.mjs`) never touches the DOM or CodeMirror at module load
// time. `cellsToBody` and its helpers above remain pure and DOM-free.
// -----------------------------------------------------------------------

/**
 * The four cell kinds that can be freely chosen when adding a new cell or
 * changing an existing (non-`scene`) cell's kind. `scene` is deliberately
 * excluded here: it is a legacy/authoring-only kind that must be preserved
 * when already present on a cell, but is never offered as a fresh choice.
 */
const EDITABLE_KINDS = ['prose', 'code-eval', 'code-exercise', 'code-solution'];

/**
 * Human-readable labels for each cell kind, used in `<select>` options. The
 * `prose` kind is labelled "Markdown" (its body is written in Markdown, à la
 * Jupyter's Markdown cell); the internal kind string and `===prose===` fence
 * are unchanged.
 */
const KIND_LABELS = {
  prose: 'Markdown',
  'code-eval': 'Code (eval)',
  'code-exercise': 'Code (exercise)',
  'code-solution': 'Code (solution)',
  scene: 'Scene',
};

/**
 * Font Awesome 6 (free, solid) icon path data for the small set of glyphs the
 * cell editor uses for its controls. Inlined as SVG so the editor needs no
 * external font/CSS dependency and works offline; `currentColor` lets CSS drive
 * the colour.
 */
const ICON_PATHS = {
  'arrow-up': {
    viewBox: '0 0 384 512',
    d: 'M214.6 41.4c-12.5-12.5-32.8-12.5-45.3 0l-160 160c-12.5 12.5-12.5 32.8 0 45.3s32.8 12.5 45.3 0L160 141.2V448c0 17.7 14.3 32 32 32s32-14.3 32-32V141.2L329.4 246.6c12.5 12.5 32.8 12.5 45.3 0s12.5-32.8 0-45.3l-160-160z',
  },
  'arrow-down': {
    viewBox: '0 0 384 512',
    d: 'M169.4 470.6c12.5 12.5 32.8 12.5 45.3 0l160-160c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0L224 370.8V64c0-17.7-14.3-32-32-32s-32 14.3-32 32V370.8L54.6 265.4c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3l160 160z',
  },
  trash: {
    viewBox: '0 0 448 512',
    d: 'M135.2 17.7L128 32H32C14.3 32 0 46.3 0 64S14.3 96 32 96H416c17.7 0 32-14.3 32-32s-14.3-32-32-32H320l-7.2-14.3C307.4 6.8 296.3 0 284.2 0H163.8c-12.1 0-23.2 6.8-28.6 17.7zM416 128H32L53.2 467c1.6 25.3 22.6 45 47.9 45H346.9c25.3 0 46.3-19.7 47.9-45L416 128z',
  },
  plus: {
    viewBox: '0 0 448 512',
    d: 'M256 80c0-17.7-14.3-32-32-32s-32 14.3-32 32V224H48c-17.7 0-32 14.3-32 32s14.3 32 32 32H192V432c0 17.7 14.3 32 32 32s32-14.3 32-32V288H400c17.7 0 32-14.3 32-32s-14.3-32-32-32H256V80z',
  },
};

/**
 * Build an inline SVG element for one of the ICON_PATHS glyphs, sized in `em`
 * so it scales with the button font-size and inherits colour via
 * `currentColor`. Marked `aria-hidden` since the enclosing control carries the
 * accessible label.
 *
 * @param {string} name key into ICON_PATHS
 * @returns {SVGSVGElement}
 */
function icon(name) {
  const spec = ICON_PATHS[name];
  const NS = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('viewBox', spec.viewBox);
  svg.setAttribute('width', '1em');
  svg.setAttribute('height', '1em');
  svg.setAttribute('fill', 'currentColor');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  const path = document.createElementNS(NS, 'path');
  path.setAttribute('d', spec.d);
  svg.appendChild(path);
  return svg;
}

/**
 * Build an icon-only `<button>` (no visible text) with an accessible label
 * exposed via `title` + `aria-label`, so it degrades to a tooltip and stays
 * screen-reader friendly. Pass `opts.danger` for destructive actions and
 * `opts.disabled` to render it disabled.
 *
 * @param {string} iconName key into ICON_PATHS
 * @param {string} label accessible label / tooltip
 * @param {() => void} onClick
 * @param {{danger?: boolean, disabled?: boolean}} [opts]
 * @returns {HTMLButtonElement}
 */
function iconButton(iconName, label, onClick, opts = {}) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = opts.danger
    ? 'cell-editor-icon-btn danger'
    : 'cell-editor-icon-btn';
  button.title = label;
  button.setAttribute('aria-label', label);
  if (opts.disabled) {
    button.disabled = true;
  }
  button.appendChild(icon(iconName));
  button.addEventListener('click', onClick);
  return button;
}

/**
 * Build a labelled action `<button>` (icon + visible text), used for the "add"
 * actions (add cell, add test case).
 *
 * @param {string} iconName key into ICON_PATHS
 * @param {string} label visible button text
 * @param {() => void} onClick
 * @returns {HTMLButtonElement}
 */
function labeledButton(iconName, label, onClick) {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'cell-editor-btn';
  button.appendChild(icon(iconName));
  button.appendChild(document.createTextNode(label));
  button.addEventListener('click', onClick);
  return button;
}

/**
 * Convert a server-shaped cell (as produced by Lisp `cell->jsonb-form` and
 * read from `data-cells`) into the internal editor state shape used by the
 * UI. Pure and DOM-free.
 *
 * @param {{"cell-id"?: string, kind: string, body?: string, description?: string, "test-cases"?: Array, gated?: boolean}} serverCell
 * @returns {{cellId: string, kind: string, body: string, description: string, testCases: Array<{input: string, expected: string, description: string}>, gated: boolean, view: null, descView: null}}
 */
export function serverCellToState(serverCell) {
  // The server serializes an empty test-case list as JSON `false` (the Lisp
  // nil -> false quirk), not `[]`. `?? []` only defaults null/undefined, so it
  // would leave `false` in place and `false.map(...)` would throw — dropping
  // the whole editor into its textarea fallback whenever a notebook has any
  // cell without test-cases (i.e. every edit of a real notebook). Guard with
  // Array.isArray so any non-array (false/null/missing) becomes [].
  const rawTestCases = serverCell['test-cases'];
  const testCases = Array.isArray(rawTestCases) ? rawTestCases : [];
  return {
    cellId: serverCell['cell-id'] ?? '',
    // Fall back to 'prose' so a kind-less cell can never leave `kind`
    // undefined, which would later make `renderCellHeader` throw at submit
    // time (consistent with the `?? ''` fallbacks on the other fields).
    kind: serverCell.kind ?? 'prose',
    body: serverCell.body ?? '',
    description: serverCell.description ?? '',
    testCases: testCases.map((tc) => ({
      input: tc.input ?? '',
      expected: tc.expected ?? '',
      description: tc.description ?? '',
    })),
    gated: serverCell.gated === true,
    view: null,
    descView: null,
  };
}

/**
 * Convert an internal editor state cell back into the server-shaped cell
 * object consumed by `cellsToBody` (and, ultimately, matching the Lisp
 * `cells->body-md` fence format). Pure and DOM-free: reads only plain data
 * fields off `stateCell`, never `stateCell.view`.
 *
 * @param {{cellId?: string, kind: string, body?: string, description?: string, testCases?: Array<{input?: string, expected?: string, description?: string}>, gated?: boolean}} stateCell
 * @returns {{"cell-id": string, kind: string, body: string, description: string, "test-cases": Array, gated: boolean}}
 */
export function stateCellToServer(stateCell) {
  return {
    'cell-id': stateCell.cellId ?? '',
    kind: stateCell.kind,
    body: stateCell.body ?? '',
    description: stateCell.description ?? '',
    'test-cases': (stateCell.testCases ?? []).map((tc) => ({
      input: tc.input ?? '',
      expected: tc.expected ?? '',
      description: tc.description ?? '',
    })),
    gated: stateCell.gated === true,
  };
}

/**
 * A fresh, empty internal editor state cell of the given kind (no live view
 * yet). Single source of truth for the internal cell shape, used both to
 * seed the editor (`data-cells` empty / last cell deleted) and to append a
 * new cell from the toolbar.
 *
 * @param {string} kind
 * @returns {{cellId: string, kind: string, body: string, description: string, testCases: Array, gated: boolean, view: null, descView: null}}
 */
function emptyCell(kind) {
  return {
    cellId: '',
    kind,
    body: '',
    description: '',
    testCases: [],
    gated: false,
    view: null,
    descView: null,
  };
}

/**
 * Dynamically import the CodeMirror 6 packages used by the cell editor. The
 * packages are already available via the page's importmap (see
 * `web/ui/editor.lisp`); this function only performs the dynamic `import()`
 * calls and bundles the exports the editor needs into one object.
 *
 * @returns {Promise<object>} `{EditorView, EditorState, basicSetup, StreamLanguage, HighlightStyle, syntaxHighlighting, scheme, oneDark, tags}`
 */
async function loadCodeMirrorModules() {
  const [
    { EditorView },
    { EditorState },
    { basicSetup },
    { StreamLanguage, HighlightStyle, syntaxHighlighting },
    { scheme },
    { oneDark },
    { tags },
  ] = await Promise.all([
    import('@codemirror/view'),
    import('@codemirror/state'),
    import('@codemirror/basic-setup'),
    import('@codemirror/language'),
    import('@codemirror/legacy-modes/mode/scheme'),
    import('@codemirror/theme-one-dark'),
    import('@lezer/highlight'),
  ]);
  return {
    EditorView,
    EditorState,
    basicSetup,
    StreamLanguage,
    HighlightStyle,
    syntaxHighlighting,
    scheme,
    oneDark,
    tags,
  };
}

/**
 * The `<select>` kind options to offer for a given cell: the four editable
 * kinds, plus `scene` when (and only when) the cell's *current* kind is
 * already `scene` — so existing scene cells are preserved rather than
 * silently dropped, while `scene` is never offered as a new choice.
 *
 * @param {{kind: string}} cell
 * @returns {string[]}
 */
export function kindOptionsFor(cell) {
  return cell.kind === 'scene' ? [...EDITABLE_KINDS, 'scene'] : EDITABLE_KINDS;
}

/**
 * Read the current text out of every cell's live CodeMirror view(s) (if any)
 * back into that cell's `body` (and, for a `code-exercise` cell's
 * description editor, `description`), without destroying the views. Used
 * before assembling the submit payload, where views must stay mounted.
 *
 * @param {object} editorState
 */
function syncAllViewsToState(editorState) {
  for (const cell of editorState.cells) {
    if (cell.view) {
      cell.body = cell.view.state.doc.toString();
    }
    if (cell.descView) {
      cell.description = cell.descView.state.doc.toString();
    }
  }
}

/**
 * Destroy every cell's live CodeMirror view(s) (if any) and clear the
 * reference(s). Used before a full re-render so old views are never leaked
 * or left orphaned in a detached DOM subtree.
 *
 * @param {Array<{view: (object|null), descView: (object|null)}>} cells
 */
function destroyAllViews(cells) {
  for (const cell of cells) {
    if (cell.view) {
      cell.view.destroy();
      cell.view = null;
    }
    if (cell.descView) {
      cell.descView.destroy();
      cell.descView = null;
    }
  }
}

/**
 * Build a single labeled text `<input>` bound to a plain value via an
 * `input` event listener, used for test-case fields.
 *
 * @param {string} labelText
 * @param {string} value
 * @param {(value: string) => void} onChange
 * @returns {HTMLLabelElement}
 */
function buildLabeledTextInput(labelText, value, onChange) {
  const label = document.createElement('label');
  label.className = 'cell-editor-field';
  label.textContent = `${labelText}: `;
  const input = document.createElement('input');
  input.type = 'text';
  input.value = value ?? '';
  input.addEventListener('input', () => onChange(input.value));
  label.appendChild(input);
  return label;
}

/**
 * Build the kind `<select>` for a cell. Changing it updates `cell.kind` and
 * triggers a full re-render (values are synced out of live views first, so
 * body text survives a kind switch even though the CodeMirror language mode
 * changes).
 *
 * @param {object} editorState
 * @param {object} cell
 * @returns {HTMLSelectElement}
 */
function buildKindSelect(editorState, cell) {
  const select = document.createElement('select');
  select.className = 'cell-editor-kind-select';
  for (const kind of kindOptionsFor(cell)) {
    const option = document.createElement('option');
    option.value = kind;
    option.textContent = KIND_LABELS[kind] ?? kind;
    if (kind === cell.kind) {
      option.selected = true;
    }
    select.appendChild(option);
  }
  select.addEventListener('change', () => {
    cell.kind = select.value;
    renderAll(editorState);
  });
  return select;
}

/** Title input, shown only for `code-solution` cells. */
function buildTitleInput(cell) {
  return buildLabeledTextInput('Title', cell.description, (value) => {
    cell.description = value;
  });
}

/**
 * Build the "reveal only after passing" checkbox for a `code-solution` cell,
 * bound to `cell.gated`. Shown only for `code-solution` cells (see
 * `buildCellItemDom`); toggling it flips `cell.gated`, which
 * `stateCellToServer` / `renderCellHeader` use to emit the
 * `===solution-locked:===` fence variant instead of `===solution:===`.
 *
 * @param {object} cell
 * @returns {HTMLLabelElement}
 */
function buildGatedCheckbox(cell) {
  const label = document.createElement('label');
  label.className = 'cell-editor-field cell-editor-gated';
  const input = document.createElement('input');
  input.type = 'checkbox';
  input.checked = cell.gated === true;
  input.addEventListener('change', () => {
    cell.gated = input.checked;
  });
  label.appendChild(input);
  label.appendChild(
    document.createTextNode(' Reveal only after the preceding exercise is solved')
  );
  return label;
}

/**
 * A small CodeMirror 6 `StreamParser` config for Markdown highlighting.
 *
 * This deliberately does NOT pull in `@codemirror/lang-markdown` (whose Lezer
 * dependency tree cascades into lang-html/css/javascript). Instead it is a
 * lightweight line-oriented tokenizer — same shape as the Scheme legacy mode —
 * covering the constructs authors actually see: ATX headings, bold, italic,
 * inline code and fenced code blocks, links/images, blockquotes and list
 * markers. `TAGS` is `@lezer/highlight`'s `tags`, used to map token names to
 * highlight tags via `tokenTable`. Pure and DOM-free.
 *
 * @param {object} TAGS `@lezer/highlight` tags
 * @returns {object} a StreamParser config for `StreamLanguage.define`
 */
export function makeMarkdownStreamParser(TAGS) {
  return {
    name: 'markdown-lite',
    startState() {
      return { fenced: false };
    },
    token(stream, state) {
      // Inside a fenced code block: consume whole lines as code until the
      // closing fence.
      if (state.fenced) {
        if (stream.sol() && stream.match(/^\s*(```|~~~)/)) {
          state.fenced = false;
          stream.skipToEnd();
          return 'md-meta';
        }
        stream.skipToEnd();
        return 'md-monospace';
      }
      if (stream.sol()) {
        if (stream.match(/^\s*(```|~~~)/)) {
          state.fenced = true;
          stream.skipToEnd();
          return 'md-meta';
        }
        if (stream.match(/^#{1,6}\s.*/)) {
          return 'md-heading';
        }
        if (stream.match(/^\s*>+\s?/)) {
          return 'md-quote';
        }
        if (stream.match(/^\s*(?:[-*+]|\d+\.)\s/)) {
          return 'md-list';
        }
        // Otherwise fall through to scan the rest of the line inline.
      }
      if (stream.match(/^`[^`\n]+`/)) {
        return 'md-monospace';
      }
      if (stream.match(/^(\*\*|__)(?=\S)(?:[\s\S]*?\S)\1/)) {
        return 'md-strong';
      }
      if (stream.match(/^(\*|_)(?=\S)(?:[^*_\n]*?\S)\1/)) {
        return 'md-emphasis';
      }
      if (stream.match(/^!?\[[^\]\n]*\]\([^)\n]*\)/)) {
        return 'md-link';
      }
      // No token here: advance one character so the tokenizer always makes
      // progress.
      stream.next();
      return null;
    },
    tokenTable: {
      'md-heading': TAGS.heading,
      'md-strong': TAGS.strong,
      'md-emphasis': TAGS.emphasis,
      'md-monospace': TAGS.monospace,
      'md-link': TAGS.link,
      'md-quote': TAGS.quote,
      'md-list': TAGS.list,
      'md-meta': TAGS.meta,
    },
  };
}

/**
 * Build the Markdown language + highlight extensions from loaded CM modules.
 * A dedicated `HighlightStyle` pins explicit colours (matched to the one-dark
 * palette) for the Markdown tags so highlighting is visible regardless of what
 * the base theme happens to cover; placed before `oneDark` so it wins.
 *
 * @param {object} cm loaded CodeMirror modules (from `loadCodeMirrorModules`)
 * @returns {Array} extensions enabling Markdown highlighting
 */
function markdownExtensions(cm) {
  const { StreamLanguage, HighlightStyle, syntaxHighlighting, tags } = cm;
  const style = HighlightStyle.define([
    { tag: tags.heading, color: '#e5c07b', fontWeight: 'bold' },
    { tag: tags.strong, color: '#e5c07b', fontWeight: 'bold' },
    { tag: tags.emphasis, color: '#c678dd', fontStyle: 'italic' },
    { tag: tags.monospace, color: '#98c379' },
    { tag: tags.link, color: '#61afef', textDecoration: 'underline' },
    { tag: tags.quote, color: '#7f848e', fontStyle: 'italic' },
    { tag: tags.list, color: '#61afef' },
    { tag: tags.meta, color: '#7f848e' },
  ]);
  return [
    StreamLanguage.define(makeMarkdownStreamParser(tags)),
    syntaxHighlighting(style),
  ];
}

/**
 * The CodeMirror extensions for a cell of the given KIND: Scheme highlighting
 * for the three code kinds, Markdown highlighting for `prose`, and plain text
 * for `scene` (and any other/legacy kind).
 *
 * @param {string} kind
 * @param {object} cm loaded CodeMirror modules
 * @returns {Array} the extensions array for `EditorState.create`
 */
function editorExtensionsForKind(kind, cm) {
  const { basicSetup, StreamLanguage, scheme, oneDark } = cm;
  const isCode =
    kind === 'code-eval' || kind === 'code-exercise' || kind === 'code-solution';
  if (isCode) {
    return [basicSetup, StreamLanguage.define(scheme), oneDark];
  }
  if (kind === 'prose') {
    return [basicSetup, ...markdownExtensions(cm), oneDark];
  }
  return [basicSetup, oneDark];
}

/**
 * Mount a fresh CodeMirror 6 `EditorView` for a cell's body text and store
 * it on `cell.view`. Mode is Markdown for `prose`, Scheme for the three code
 * kinds, and plain text for `scene`.
 *
 * @param {object} editorState
 * @param {object} cell
 * @returns {HTMLDivElement} the mount element containing the CM view
 */
function buildEditorMount(editorState, cell) {
  const mount = document.createElement('div');
  mount.className = 'cell-editor-cm-mount';

  const { EditorView, EditorState } = editorState.cmModules;
  const extensions = editorExtensionsForKind(cell.kind, editorState.cmModules);

  const view = new EditorView({
    state: EditorState.create({ doc: cell.body ?? '', extensions }),
    parent: mount,
  });
  cell.view = view;

  return mount;
}

/**
 * Mount a Markdown-highlighted CodeMirror editor for a `code-exercise`
 * cell's description (the problem statement), storing the view on
 * `cell.descView`. Reuses the same Markdown extensions as a `prose` cell's
 * body editor (see `editorExtensionsForKind`), since the description is
 * itself free-form Markdown that can span multiple lines/paragraphs.
 *
 * @param {object} editorState
 * @param {object} cell
 * @returns {HTMLDivElement} the field wrapper containing the label and CM view
 */
function buildDescriptionEditor(editorState, cell) {
  const wrap = document.createElement('div');
  wrap.className = 'cell-editor-field cell-editor-desc';
  const label = document.createElement('div');
  label.className = 'cell-editor-desc-label';
  label.textContent = 'Description (Markdown)';
  wrap.appendChild(label);

  const mount = document.createElement('div');
  mount.className = 'cell-editor-cm-mount';
  wrap.appendChild(mount);

  const { EditorView, EditorState } = editorState.cmModules;
  const extensions = editorExtensionsForKind('prose', editorState.cmModules);
  const view = new EditorView({
    state: EditorState.create({ doc: cell.description ?? '', extensions }),
    parent: mount,
  });
  cell.descView = view;

  return wrap;
}

/**
 * Build one test-case row (input / expected / description fields + a
 * delete button) for a `code-exercise` cell.
 *
 * @param {object} editorState
 * @param {object} cell
 * @param {number} tcIndex index into `cell.testCases`
 * @returns {HTMLDivElement}
 */
function buildTestCaseRow(editorState, cell, tcIndex) {
  const tc = cell.testCases[tcIndex];
  const row = document.createElement('div');
  row.className = 'cell-editor-testcase-row';

  row.appendChild(
    buildLabeledTextInput('input', tc.input, (value) => {
      tc.input = value;
    })
  );
  row.appendChild(
    buildLabeledTextInput('expected', tc.expected, (value) => {
      tc.expected = value;
    })
  );
  row.appendChild(
    buildLabeledTextInput('description', tc.description, (value) => {
      tc.description = value;
    })
  );

  row.appendChild(
    iconButton(
      'trash',
      'Delete test case',
      () => {
        cell.testCases.splice(tcIndex, 1);
        renderAll(editorState);
      },
      { danger: true }
    )
  );

  return row;
}

/**
 * Build the test-cases section (rows + "add" button) for a `code-exercise`
 * cell.
 *
 * @param {object} editorState
 * @param {object} cell
 * @returns {HTMLDivElement}
 */
function buildTestCasesSection(editorState, cell) {
  const section = document.createElement('div');
  section.className = 'cell-editor-testcases';

  cell.testCases.forEach((_tc, tcIndex) => {
    section.appendChild(buildTestCaseRow(editorState, cell, tcIndex));
  });

  section.appendChild(
    labeledButton('plus', 'Add test case', () => {
      cell.testCases.push({ input: '', expected: '', description: '' });
      renderAll(editorState);
    })
  );

  return section;
}

/**
 * Move a cell within `editorState.cells` from `fromIndex` to `toIndex`
 * (no-op if `toIndex` is out of bounds) and re-render.
 *
 * @param {object} editorState
 * @param {number} fromIndex
 * @param {number} toIndex
 */
function moveCell(editorState, fromIndex, toIndex) {
  const { cells } = editorState;
  if (toIndex < 0 || toIndex >= cells.length) {
    return;
  }
  const [cell] = cells.splice(fromIndex, 1);
  cells.splice(toIndex, 0, cell);
  renderAll(editorState);
}

/**
 * Remove a cell from `editorState.cells` and re-render. If the list would
 * become empty, a fresh `prose` cell is seeded back in, mirroring the
 * initial-state rule for an empty `data-cells` array.
 *
 * @param {object} editorState
 * @param {number} index
 */
function deleteCell(editorState, index) {
  const { cells } = editorState;
  const [removed] = cells.splice(index, 1);
  // The removed cell is no longer in `cells`, so the `renderAll` below (which
  // only destroys views still in the array) would never reach its view.
  // Destroy it here to avoid leaking an orphaned CodeMirror instance.
  if (removed && removed.view) {
    removed.view.destroy();
    removed.view = null;
  }
  if (removed && removed.descView) {
    removed.descView.destroy();
    removed.descView = null;
  }
  if (cells.length === 0) {
    cells.push(emptyCell('prose'));
  }
  renderAll(editorState);
}

/**
 * Build the per-cell move-up / move-down / delete controls.
 *
 * @param {object} editorState
 * @param {number} index
 * @returns {HTMLDivElement}
 */
function buildCellControls(editorState, index) {
  const controls = document.createElement('div');
  controls.className = 'cell-editor-controls';

  controls.appendChild(
    iconButton('arrow-up', 'Move cell up', () => moveCell(editorState, index, index - 1), {
      disabled: index === 0,
    })
  );
  controls.appendChild(
    iconButton('arrow-down', 'Move cell down', () => moveCell(editorState, index, index + 1), {
      disabled: index === editorState.cells.length - 1,
    })
  );
  controls.appendChild(
    iconButton('trash', 'Delete cell', () => deleteCell(editorState, index), { danger: true })
  );
  return controls;
}

/**
 * Build the full DOM subtree for one cell: header (kind select, optional
 * `code-solution` title + gated checkbox, move/delete controls), a
 * Markdown-highlighted description editor for `code-exercise` cells, the
 * body CodeMirror mount, and (for `code-exercise`) the test-cases section.
 *
 * @param {object} editorState
 * @param {object} cell
 * @param {number} index
 * @returns {HTMLDivElement}
 */
function buildCellItemDom(editorState, cell, index) {
  const item = document.createElement('div');
  item.className = 'cell-editor-item';
  item.dataset.cellIndex = String(index);

  const header = document.createElement('div');
  header.className = 'cell-editor-item-header';
  header.appendChild(buildKindSelect(editorState, cell));
  if (cell.kind === 'code-solution') {
    header.appendChild(buildTitleInput(cell));
    header.appendChild(buildGatedCheckbox(cell));
  }
  header.appendChild(buildCellControls(editorState, index));
  item.appendChild(header);

  if (cell.kind === 'code-exercise') {
    item.appendChild(buildDescriptionEditor(editorState, cell));
  }

  item.appendChild(buildEditorMount(editorState, cell));

  if (cell.kind === 'code-exercise') {
    item.appendChild(buildTestCasesSection(editorState, cell));
  }

  return item;
}

/**
 * Build the "Add cell" toolbar: a kind `<select>` (never offering `scene`)
 * plus a button that appends a fresh cell of the chosen kind and re-renders.
 *
 * @param {object} editorState
 * @returns {HTMLDivElement}
 */
function buildToolbarDom(editorState) {
  const toolbar = document.createElement('div');
  toolbar.className = 'cell-editor-toolbar';

  const select = document.createElement('select');
  select.className = 'cell-editor-add-kind-select';
  for (const kind of EDITABLE_KINDS) {
    const option = document.createElement('option');
    option.value = kind;
    option.textContent = KIND_LABELS[kind] ?? kind;
    select.appendChild(option);
  }

  const addButton = labeledButton('plus', 'Add cell', () => {
    editorState.cells.push(emptyCell(select.value));
    renderAll(editorState);
  });

  toolbar.appendChild(select);
  toolbar.appendChild(addButton);
  return toolbar;
}

/**
 * Rebuild `editorState.root`'s children from scratch: the cell list plus
 * the "add cell" toolbar. Assumes any previous CodeMirror views have
 * already been destroyed (see `renderAll`).
 *
 * @param {object} editorState
 */
function renderCellEditorDom(editorState) {
  const { root, cells } = editorState;
  root.innerHTML = '';

  const list = document.createElement('div');
  list.className = 'cell-editor-list';
  cells.forEach((cell, index) => {
    list.appendChild(buildCellItemDom(editorState, cell, index));
  });
  root.appendChild(list);

  root.appendChild(buildToolbarDom(editorState));
}

/**
 * Full re-render entry point used by every structural mutation (kind
 * change, add, delete, move): sync live view text back into state, destroy
 * all live views, then rebuild the DOM (and fresh views) from
 * `editorState.cells`. Safe to call for the very first render too, when no
 * views exist yet.
 *
 * @param {object} editorState
 */
function renderAll(editorState) {
  syncAllViewsToState(editorState);
  destroyAllViews(editorState.cells);
  renderCellEditorDom(editorState);
}

/**
 * Initialize the cell editor UI in place of `#cell-editor-root`, or fall
 * back to leaving the plain `#body` textarea as the editing surface if
 * CodeMirror can't be loaded or initialization otherwise fails. Wires a
 * `submit` handler on the containing `form.nb-form` that assembles the
 * fence-format body from the live cell state and writes it into `#body`
 * just before the form submits normally (no `preventDefault`).
 *
 * @returns {Promise<void>}
 */
async function initCellEditor() {
  const root = document.getElementById('cell-editor-root');
  if (!root) {
    return;
  }

  const bodyField = document.getElementById('body');
  let editorState = null;

  try {
    const cmModules = await loadCodeMirrorModules();
    const rawCells = JSON.parse(root.dataset.cells || '[]');
    const cells = rawCells.length > 0 ? rawCells.map(serverCellToState) : [emptyCell('prose')];

    editorState = { root, cmModules, cells };
    renderAll(editorState);

    if (bodyField) {
      // The cell editor is now the source of truth; `#body` becomes a hidden
      // carrier populated on submit. Drop its `required` so the browser's
      // constraint validation doesn't block submit on the (initially empty)
      // hidden field before the submit handler below can fill it — otherwise a
      // brand-new notebook (empty `#body`) could never be created. The server
      // still validates that the assembled body is non-empty.
      bodyField.style.display = 'none';
      bodyField.removeAttribute('required');
    }

    // The fence-syntax cheatsheet only helps when editing raw fence markdown in
    // the plain textarea. With the cell editor active it is redundant, so hide
    // it here (success path only) — the no-JS / fallback path leaves it visible.
    const cheatsheet = document.querySelector('.cheatsheet');
    if (cheatsheet) {
      cheatsheet.style.display = 'none';
    }

    const form = bodyField ? bodyField.closest('form.nb-form') : root.closest('form.nb-form');
    if (form) {
      form.addEventListener('submit', (event) => {
        try {
          syncAllViewsToState(editorState);
          const serverCells = editorState.cells.map(stateCellToServer);
          if (bodyField) {
            bodyField.value = cellsToBody(serverCells);
          }
        } catch (submitErr) {
          // The hidden `#body` still holds the pre-edit content, so letting
          // the form submit would silently discard the user's edits. Block
          // the submit and surface the failure so nothing is lost.
          event.preventDefault();
          console.error('cell-editor: failed to assemble notebook body on submit', submitErr);
          window.alert('Failed to assemble the notebook body. Please reload the page.');
        }
      });
    } else {
      console.warn('cell-editor: form.nb-form not found; body will not be assembled on submit');
    }
  } catch (err) {
    console.warn('cell-editor: CodeMirror cell editor unavailable, falling back to plain textarea', err);
    if (editorState) {
      try {
        destroyAllViews(editorState.cells);
      } catch (cleanupErr) {
        console.error('cell-editor: cleanup after fallback failed', cleanupErr);
      }
    }
    root.style.display = 'none';
    if (bodyField) {
      // Fallback: the plain textarea is the editing surface again, so restore
      // its `required` constraint (it may have been dropped if we got as far as
      // handing off to the cell editor before failing).
      bodyField.style.display = '';
      bodyField.setAttribute('required', 'required');
    }
  }
}

/**
 * Run `initCellEditor` once the DOM is ready (immediately if it already is,
 * otherwise on `DOMContentLoaded`).
 */
function bootstrapCellEditor() {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      initCellEditor();
    });
  } else {
    initCellEditor();
  }
}

// Browser-only bootstrap. Guarded so that importing this module under plain
// Node.js (see `cell-editor.test.mjs`) never touches `document`.
if (typeof document !== 'undefined') {
  bootstrapCellEditor();
}
