import {
  cellsToBody,
  serverCellToState,
  stateCellToServer,
  kindOptionsFor,
} from './cell-editor.js';
import assert from 'node:assert';

// Fixtures use the canonical server `data-cells` shape (kebab keys such as
// `test-cases`, and per-test-case `expected`), i.e. exactly what
// JSON.parse(dataCells) yields from Lisp cell->jsonb-form.

const cells = [
  { kind: 'prose', body: 'Intro.' },
  { kind: 'code-eval', body: '(+ 1 2)' },
  { kind: 'code-exercise', description: 'sum', body: '; ?',
    'test-cases': [{ description: 'sum', input: '', expected: '3' }] },
  { kind: 'code-solution', description: 'sq', body: '(define (sq x) (* x x))' },
];
const expected =
  '===prose===\nIntro.\n\n' +
  '===eval===\n(+ 1 2)\n\n' +
  '===exercise: sum===\n; ?\n\n===expect: sum===\n3\n\n' +
  '===solution: sq===\n(define (sq x) (* x x))';
assert.strictEqual(cellsToBody(cells), expected);
console.log('ok');

// Empty cell list → empty string.
assert.strictEqual(cellsToBody([]), '');

// Additional cases beyond the plan's baseline, verified against the
// serialization rules transcribed from the Lisp cells->body-md/render-cell/
// render-test-case.

// scene cell → header only, no description
{
  const sceneCells = [{ kind: 'scene', body: 'A scene body.' }];
  const sceneExpected = '===scene===\nA scene body.';
  assert.strictEqual(cellsToBody(sceneCells), sceneExpected);
}

// non-empty input → two-line "input: ...\noutput: ..." test-case body
{
  const inputCells = [
    { kind: 'code-exercise', description: 'add', body: '(+ a b)',
      'test-cases': [{ description: 'basic', input: '(zero? 0)', expected: 't' }] },
  ];
  const inputExpected =
    '===exercise: add===\n(+ a b)\n\n===expect: basic===\ninput: (zero? 0)\noutput: t';
  assert.strictEqual(cellsToBody(inputCells), inputExpected);
}

// multiple test-cases, including an empty description (===expect=== header)
{
  const multiCells = [
    { kind: 'code-exercise', description: 'double', body: '(* x 2)',
      'test-cases': [
        { description: '', input: '', expected: '4' },
        { description: 'neg', input: '-1', expected: '-2' },
      ] },
  ];
  const multiExpected =
    '===exercise: double===\n(* x 2)\n\n===expect===\n4\n\n===expect: neg===\ninput: -1\noutput: -2';
  assert.strictEqual(cellsToBody(multiCells), multiExpected);
}

console.log('ok: additional cases (empty list, scene, non-empty input, multiple test-cases)');

// serverCellToState / stateCellToServer / cellsToBody round trip: a
// representative mix of cell kinds (prose, code-eval, code-exercise with
// multiple test-cases, code-solution, scene) taken through the internal
// editor state shape and back out should serialize identically to feeding
// the original server-shaped cells straight into cellsToBody. This is the
// pure (DOM-free) half of the browser submit-time conversion.
{
  const serverCells = [
    { 'cell-id': 'c1', kind: 'prose', body: 'Hello.', description: null, 'test-cases': [] },
    { 'cell-id': '', kind: 'code-eval', body: '(+ 1 2)', description: '', 'test-cases': [] },
    {
      'cell-id': '',
      kind: 'code-exercise',
      body: '; ?',
      description: 'sum',
      'test-cases': [
        { description: 'sum', input: '', expected: '3' },
        { description: 'basic', input: '(zero? 0)', expected: 't' },
      ],
    },
    {
      'cell-id': '',
      kind: 'code-solution',
      body: '(define (sq x) (* x x))',
      description: 'sq',
      'test-cases': [],
    },
    { 'cell-id': '', kind: 'scene', body: 'A scene body.', description: null, 'test-cases': [] },
  ];

  const roundTripped = serverCells.map(serverCellToState).map(stateCellToServer);
  assert.strictEqual(cellsToBody(roundTripped), cellsToBody(serverCells));

  // cell-id survives the round trip (kept in state even though cellsToBody
  // itself never reads it).
  assert.strictEqual(roundTripped[0]['cell-id'], 'c1');
}

console.log('ok: serverCellToState/stateCellToServer round trip matches cellsToBody');

// kindOptionsFor: `scene` is preserved as an option only when the cell is
// already a scene cell; otherwise exactly the four editable kinds are offered
// (scene is never a fresh choice).
{
  assert.deepStrictEqual(kindOptionsFor({ kind: 'scene' }), [
    'prose',
    'code-eval',
    'code-exercise',
    'code-solution',
    'scene',
  ]);
  assert.deepStrictEqual(kindOptionsFor({ kind: 'prose' }), [
    'prose',
    'code-eval',
    'code-exercise',
    'code-solution',
  ]);
  assert.ok(!kindOptionsFor({ kind: 'code-eval' }).includes('scene'));
}

console.log('ok: kindOptionsFor preserves scene only for existing scene cells');
