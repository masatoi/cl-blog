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
 * Render the header line for a cell, given its kind and (for
 * exercise/solution cells) description.
 *
 * @param {string} kind
 * @param {string} description
 * @returns {string}
 */
function renderCellHeader(kind, description) {
  switch (kind) {
    case 'prose':
      return '===prose===';
    case 'code-eval':
      return '===eval===';
    case 'scene':
      return '===scene===';
    case 'code-exercise':
      return `===exercise: ${description}===`;
    case 'code-solution':
      return `===solution: ${description}===`;
    default:
      throw new Error(`cellsToBody: unknown cell kind "${kind}"`);
  }
}

/**
 * Render a single server-shaped cell object to its fence-format text (no
 * leading/trailing cell separators).
 *
 * @param {{kind: string, body?: string, description?: string, "test-cases"?: Array}} cell
 * @returns {string}
 */
function renderCell(cell) {
  const body = cell.body ?? '';
  const description = cell.description ?? '';
  const header = renderCellHeader(cell.kind, description);

  let rendered = `${header}\n${body}`;

  if (cell.kind === 'code-exercise') {
    const testCases = cell['test-cases'] ?? [];
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
 * @param {Array<{kind: string, body?: string, description?: string, "test-cases"?: Array}>} cells
 * @returns {string}
 */
export function cellsToBody(cells) {
  return cells.map(renderCell).join('\n\n');
}
