import {
  cellsToBody,
  serverCellToState,
  stateCellToServer,
  kindOptionsFor,
  makeMarkdownStreamParser,
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
  '===exercise===\nsum\n===code===\n; ?\n\n===expect: sum===\n3\n\n' +
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
    '===exercise===\nadd\n===code===\n(+ a b)\n\n===expect: basic===\ninput: (zero? 0)\noutput: t';
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
    '===exercise===\ndouble\n===code===\n(* x 2)\n\n===expect===\n4\n\n===expect: neg===\ninput: -1\noutput: -2';
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

// Lisp <-> JS fence parity (Task 5): the JS `cellsToBody` output must match the
// server's Lisp `recurya/game/notebook-parser:cells->body-md` byte-for-byte for
// a representative mix of every cell kind and every test-case variant (desc +
// single-line expected, bare `===expect===`, and the two-line input/output
// form). `LISP_BODY_MD` below was originally the exact string returned by
// evaluating the following in the running image (JSON-encoded so newlines
// transfer unambiguously); the `code-exercise` fence has since been updated
// to the new `===exercise===\n<desc>\n===code===\n<body>` block form (Task 3,
// matching the Lisp side's own move to that format) — every other line is
// unchanged from that original REPL output:
//
//   (recurya/utils/common:json->string
//    (recurya/game/notebook-parser:cells->body-md
//     (list
//      (recurya/game/notebook:make-cell :id "" :kind :prose
//        :body (format nil "Intro paragraph.~%Second line with **bold**.")
//        :description "" :test-cases nil)
//      (recurya/game/notebook:make-cell :id "" :kind :code-eval
//        :body "(+ 1 2)" :description "" :test-cases nil)
//      (recurya/game/notebook:make-cell :id "" :kind :code-exercise
//        :body "; fill me in" :description "double it"
//        :test-cases (list
//         (recurya/game/puzzle:make-test-case :input "" :expected "4" :description "even")
//         (recurya/game/puzzle:make-test-case :input "" :expected "0" :description "")
//         (recurya/game/puzzle:make-test-case :input "(f 3)" :expected "6" :description "positive")))
//      (recurya/game/notebook:make-cell :id "" :kind :code-solution
//        :body "(define (double x) (* x 2))" :description "double soln" :test-cases nil)
//      (recurya/game/notebook:make-cell :id "" :kind :scene
//        :body "A quiet room." :description "" :test-cases nil))))
{
  const LISP_BODY_MD =
    '===prose===\nIntro paragraph.\nSecond line with **bold**.\n\n' +
    '===eval===\n(+ 1 2)\n\n' +
    '===exercise===\ndouble it\n===code===\n; fill me in\n\n' +
    '===expect: even===\n4\n\n' +
    '===expect===\n0\n\n' +
    '===expect: positive===\ninput: (f 3)\noutput: 6\n\n' +
    '===solution: double soln===\n(define (double x) (* x 2))\n\n' +
    '===scene===\nA quiet room.';

  // Same cells in the canonical server `data-cells` shape the browser reads.
  const parityCells = [
    { 'cell-id': '', kind: 'prose',
      body: 'Intro paragraph.\nSecond line with **bold**.',
      description: '', 'test-cases': [] },
    { 'cell-id': '', kind: 'code-eval', body: '(+ 1 2)',
      description: '', 'test-cases': [] },
    { 'cell-id': '', kind: 'code-exercise', body: '; fill me in',
      description: 'double it',
      'test-cases': [
        { input: '', expected: '4', description: 'even' },
        { input: '', expected: '0', description: '' },
        { input: '(f 3)', expected: '6', description: 'positive' },
      ] },
    { 'cell-id': '', kind: 'code-solution',
      body: '(define (double x) (* x 2))',
      description: 'double soln', 'test-cases': [] },
    { 'cell-id': '', kind: 'scene', body: 'A quiet room.',
      description: '', 'test-cases': [] },
  ];

  assert.strictEqual(cellsToBody(parityCells), LISP_BODY_MD);
}

console.log('ok: JS cellsToBody matches Lisp cells->body-md (fence parity)');

// Regression (edit form went to textarea fallback): the server's json->string
// serializes an EMPTY test-case list as JSON `false`, not `[]` (Lisp nil ->
// false). Every real notebook has at least one cell without test-cases, so
// `data-cells` always contains `"test-cases":false`. serverCellToState and
// cellsToBody must tolerate it instead of throwing on `.map` / `for...of`.
{
  // Exact shape of a prose/eval cell as emitted by cell->jsonb-form + json->string.
  const proseFromServer = {
    'cell-id': 'abc', kind: 'prose', body: 'hi', description: '', 'test-cases': false,
  };
  const state = serverCellToState(proseFromServer); // must not throw
  assert.deepStrictEqual(state.testCases, []);
  // Round trips cleanly back through the fence serializer.
  assert.strictEqual(cellsToBody([stateCellToServer(state)]), '===prose===\nhi');

  // A code-exercise carrying `false` (no test-cases) must render header+body only.
  const exerciseFalse = {
    'cell-id': '', kind: 'code-exercise', body: '; x', description: 'd', 'test-cases': false,
  };
  assert.strictEqual(cellsToBody([exerciseFalse]), '===exercise===\nd\n===code===\n; x');
}

console.log('ok: tolerates test-cases:false (Lisp nil->false) without falling back');

// Markdown StreamParser (prose highlighting). We can't render CodeMirror in
// Node, but the tokenizer is a pure StreamParser: exercise its token() against
// a faithful mock of CodeMirror's StringStream (regex match must be anchored
// at pos, and every call must advance the stream).
{
  class MockStream {
    constructor(line) {
      this.string = line;
      this.pos = 0;
      this.start = 0;
    }
    sol() {
      return this.pos === 0;
    }
    eol() {
      return this.pos >= this.string.length;
    }
    next() {
      return this.pos < this.string.length ? this.string.charAt(this.pos++) : undefined;
    }
    match(pattern, consume) {
      const m = this.string.slice(this.pos).match(pattern);
      if (m && m.index > 0) return null;
      if (m && consume !== false) this.pos += m[0].length;
      return m;
    }
    skipToEnd() {
      this.pos = this.string.length;
    }
  }

  // Non-null tags stub: token() never reads it, but tokenTable is built eagerly.
  const tagsStub = {
    heading: 'h', strong: 's', emphasis: 'e', monospace: 'm',
    link: 'l', quote: 'q', list: 'li', meta: 'me',
  };
  const parser = makeMarkdownStreamParser(tagsStub);

  function tokenize(line, state) {
    const stream = new MockStream(line);
    const out = [];
    let guard = 0;
    while (!stream.eol()) {
      if (guard++ > 1000) throw new Error('tokenizer did not terminate');
      stream.start = stream.pos;
      const style = parser.token(stream, state);
      if (stream.pos === stream.start) stream.pos++; // must never stall
      out.push({ text: line.slice(stream.start, stream.pos), style });
    }
    return out;
  }
  const hasTok = (toks, style, text) =>
    toks.some((t) => t.style === style && (text === undefined || t.text === text));

  let st = parser.startState();
  // ATX heading: whole line.
  assert.ok(hasTok(tokenize('# Title', st), 'md-heading', '# Title'));
  // Bold / italic / inline code / link.
  assert.ok(hasTok(tokenize('a **bold** b', parser.startState()), 'md-strong', '**bold**'));
  assert.ok(hasTok(tokenize('an *em* word', parser.startState()), 'md-emphasis', '*em*'));
  assert.ok(hasTok(tokenize('use `code` here', parser.startState()), 'md-monospace', '`code`'));
  assert.ok(hasTok(tokenize('see [x](http://y)', parser.startState()), 'md-link', '[x](http://y)'));
  // Blockquote and list markers at start of line.
  assert.strictEqual(tokenize('> quoted', parser.startState())[0].style, 'md-quote');
  assert.strictEqual(tokenize('- item', parser.startState())[0].style, 'md-list');
  assert.strictEqual(tokenize('1. item', parser.startState())[0].style, 'md-list');
  // `**bold**` at start of line is bold, not a list marker.
  assert.ok(hasTok(tokenize('**b**', parser.startState()), 'md-strong', '**b**'));
  // Fenced code block spans lines via parser state.
  const fs = parser.startState();
  assert.strictEqual(tokenize('```', fs)[0].style, 'md-meta');
  assert.strictEqual(fs.fenced, true, 'opening fence sets fenced state');
  assert.strictEqual(tokenize('x = 1', fs)[0].style, 'md-monospace');
  assert.strictEqual(tokenize('```', fs)[0].style, 'md-meta');
  assert.strictEqual(fs.fenced, false, 'closing fence clears fenced state');
  // tokenTable maps token names to the provided tags.
  assert.strictEqual(parser.tokenTable['md-heading'], 'h');
  assert.strictEqual(parser.tokenTable['md-strong'], 's');
}

console.log('ok: markdown StreamParser tokenizes headings/emphasis/code/links/quotes/lists/fences');

// Gated solutions: `gated` is a boolean carried through state and encoded as
// the ===solution-locked:=== fence variant.
{
  assert.strictEqual(
    cellsToBody([{ 'cell-id': '', kind: 'code-solution', body: '(x)',
                   description: 'a', 'test-cases': [], gated: true }]),
    '===solution-locked: a===\n(x)');
  assert.strictEqual(
    cellsToBody([{ 'cell-id': '', kind: 'code-solution', body: '(x)',
                   description: 'a', 'test-cases': [], gated: false }]),
    '===solution: a===\n(x)');

  const st = serverCellToState({ 'cell-id': '', kind: 'code-solution', body: '(x)',
                                 description: 'a', 'test-cases': [], gated: true });
  assert.strictEqual(st.gated, true);
  assert.strictEqual(stateCellToServer(st).gated, true);
  const st2 = serverCellToState({ 'cell-id': '', kind: 'code-solution', body: '(x)',
                                  description: 'a', 'test-cases': [] });
  assert.strictEqual(st2.gated, false, 'missing gated => false');
}
console.log('ok: gated solutions encode ===solution-locked:=== and round-trip through state');

// Exercise cells serialize to the ===exercise===/===code=== block form with a
// multi-line Markdown description, matching Lisp cells->body-md byte-for-byte.
{
  const md = cellsToBody([{
    'cell-id': '', kind: 'code-exercise',
    description: 'para1\n\npara2', body: '(fill)',
    'test-cases': [{ input: '', expected: '3', description: '' }],
  }]);
  assert.strictEqual(
    md,
    '===exercise===\npara1\n\npara2\n===code===\n(fill)\n\n===expect===\n3');
}
console.log('ok: exercise serializes to the ===exercise===/===code=== block form');

// A solution header is a single line: a multi-line description (e.g. carried
// over when a multi-line exercise is switched to a solution) must be folded to
// one line so it cannot break re-parsing and silently drop the cell.
{
  assert.strictEqual(
    cellsToBody([{ 'cell-id': '', kind: 'code-solution', body: '(x)',
                   description: 'line1\nline2', 'test-cases': [], gated: false }]),
    '===solution: line1 line2===\n(x)');
  assert.strictEqual(
    cellsToBody([{ 'cell-id': '', kind: 'code-solution', body: '(x)',
                   description: 'a\nb', 'test-cases': [], gated: true }]),
    '===solution-locked: a b===\n(x)');
}
console.log('ok: solution header folds a multi-line description to one line');
