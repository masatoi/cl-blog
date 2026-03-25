# WardLisp MVP Design

Date: 2026-03-26
Status: Approved

## 1. Overview

WardLisp is a restricted Lisp dialect for a learning game. This MVP validates core technology: a safe server-side evaluator with resource limits, puzzle grading, and sandbox bot simulation, all accessible through a web UI.

## 2. Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Evaluator language | Common Lisp | Same stack as existing project, REPL-driven development |
| Sandbox approach | Single-process, language-level | Custom interpreter; no `cl:eval` or `cl:read`; whitelist-only builtins |
| Existing code | Coexist with blog | New routes under `/wardlisp/*`, share web stack and Docker infra |
| Bot visualization | HTML table + icons + HTMX | Minimal JS, leverage existing Spinneret/HTMX patterns |
| Puzzle storage | Hardcoded in Lisp files | Simplest for MVP, git-managed, migrate to DB later |
| Submission history | None (stateless) | No auth needed, minimal scope |
| Authentication | Not required | Anonymous usage for MVP |

## 3. Scope

### IN
- WardLisp evaluator (reader + eval + builtins)
- fuel / cons / depth / output limits
- 5 puzzles with test cases
- 7x7 arena with 1 bot vs 1 enemy, 20 turns
- Web UI: code editor, execution, result display
- Grid visualization with turn stepping
- Deterministic execution

### OUT
- Auth, user management, submission history
- Rankings, multiplayer, story, characters
- Production deploy, CI/CD, polished design

## 4. Directory Structure (additions)

```
recurya/
├── wardlisp/
│   ├── types.lisp          # Value type definitions
│   ├── reader.lisp         # Custom S-expression reader
│   ├── evaluator.lisp      # Core evaluator + resource limits
│   ├── builtins.lisp       # Whitelisted built-in functions
│   └── environment.lisp    # Lexical environment
├── game/
│   ├── puzzle.lisp         # Puzzle definition + grading
│   ├── puzzles/
│   │   ├── adjacent.lisp
│   │   ├── contains.lisp
│   │   ├── nearest-point.lisp
│   │   ├── safe-moves.lisp
│   │   └── choose-action.lisp
│   ├── arena.lisp          # Arena simulator
│   └── scenario.lisp       # Scenario definitions
├── web/
│   ├── routes-wardlisp.lisp
│   └── ui/
│       ├── wardlisp-home.lisp
│       ├── puzzle.lisp
│       └── arena.lisp
├── tests/
│   ├── wardlisp/
│   │   ├── reader.lisp
│   │   ├── evaluator.lisp
│   │   └── builtins.lisp
│   └── game/
│       ├── puzzle.lisp
│       └── arena.lisp
```

## 5. System Architecture

```
Browser (HTMX)
    │
    ├── GET /wardlisp/              → Home (puzzle list + arena link)
    ├── GET /wardlisp/puzzle/:id    → Puzzle page
    ├── POST /wardlisp/puzzle/:id/run → Execute puzzle code → HTML fragment
    ├── GET /wardlisp/arena         → Arena page
    ├── POST /wardlisp/arena/run    → Run simulation → HTML fragment
    └── GET /wardlisp/reference     → Language reference
    │
Ningle routes (web/routes-wardlisp.lisp)
    │
    ├── game/puzzle.lisp  ── uses ──→ wardlisp/evaluator.lisp
    └── game/arena.lisp   ── uses ──→ wardlisp/evaluator.lisp
```

All in a single SBCL process. No external services beyond PostgreSQL (existing, used only for blog).

## 6. WardLisp Evaluator Design

### Values
- Numbers: CL integer / rational
- Booleans: `:true` / `:false` (distinct from CL T/NIL)
- Symbols: keywords (`:up`, `:down`, etc.)
- Lists: CL cons cells
- Nil/empty: `:wnil`
- Closures: `(list :closure params body env)`

### Environment
Lexical scope via alist stack:
```lisp
((("x" . 42) ("y" . 10))   ; inner frame
 (("z" . :true)))            ; outer frame
```

### Resource Limits
```lisp
(defstruct execution-limits
  (fuel 10000)       ; max eval steps
  (max-cons 5000)    ; max cons cell allocations
  (max-depth 100)    ; max recursion depth
  (max-output 4096)) ; max output bytes

(defstruct execution-state
  (fuel-used 0)
  (cons-used 0)
  (current-depth 0)
  (output <stream>))
```

Conditions: `fuel-exhausted`, `cons-limit-exceeded`, `depth-limit-exceeded`, `output-limit-exceeded`.

### Special Forms
`if`, `let`, `lambda`, `define`, `begin`, `quote`, `and`, `or`

### Built-in Functions (whitelist)
- Arithmetic: `+`, `-`, `*`, `/`, `mod`
- Comparison: `=`, `<`, `>`, `<=`, `>=`, `equal?`
- Logic: `not`
- List: `cons`, `car`, `cdr`, `list`, `null?`, `pair?`, `length`, `append`
- Type: `number?`, `boolean?`, `symbol?`, `list?`
- Output: `print` (limit-enforced)
- Utility: `alist-ref` (for bot state access)

### Safety Guarantees
- **No `cl:read`**: Custom reader prevents reader-macro attacks
- **No `cl:eval`**: Custom interpreter only
- **No CL access**: User code cannot call any CL function not in whitelist
- **All limits enforced inside evaluator**: No external sandbox needed

## 7. Puzzle System

### Structure
```lisp
(defstruct puzzle
  id title description signature hint test-cases difficulty)

(defstruct test-case
  input expected description)
```

### Grading Flow
1. Eval user code to register function definition in environment
2. For each test case, eval the input expression in that environment
3. Compare result with expected value
4. Collect metrics (fuel/cons/depth used)
5. Return pass/fail per test + aggregate metrics

### Five Puzzles

| # | ID | Description | Concepts |
|---|-----|------------|----------|
| 1 | adjacent? | Two coords adjacent? | if, comparison, arithmetic |
| 2 | contains? | Element in list? | recursion, list ops |
| 3 | nearest-point | Closest point | recursion + comparison |
| 4 | safe-moves | Avoid walls/enemies | state structure |
| 5 | choose-action | Best action | comprehensive bot AI |

Puzzles 4-5 use Arena state structure as input, bridging to bot development.

## 8. Arena System

### State
```lisp
(defstruct arena-state
  grid        ; 7x7 2D vector (:empty :wall :resource)
  bot-pos     ; (row col)
  enemy-pos   ; (row col)
  bot-score   ; integer
  enemy-score ; integer
  turn        ; current turn
  max-turns)  ; 20
```

### State Passed to User Code (WardLisp alist)
```lisp
'((:my-pos . (3 2))
  (:enemy-pos . (5 4))
  (:my-score . 2)
  (:enemy-score . 1)
  (:turn . 5)
  (:grid . ((0 0 :wall) (1 5 :resource) ...))
  (:max-turns . 20))
```

### Actions
`:up`, `:down`, `:left`, `:right`, `:wait`, `:pickup`

### Rules
- Move into wall/out-of-bounds → stay
- `:pickup` on resource → score+1, resource removed
- Both pickup same resource same turn → bot (first) gets it
- Enemy: greedy algorithm toward nearest resource (CL-implemented)
- Deterministic: fixed scenario + fixed enemy = same code → same result

### Simulation Flow
1. Eval user code to get `decide-action` closure
2. Each turn: convert state → WardLisp alist → call `decide-action` → interpret action
3. Enemy decides via CL greedy logic
4. Apply both actions, update board
5. Record frame
6. Return all 20 frames + scores + metrics

## 9. Screen Design

### Screen 1: Home (`/wardlisp/`)
- Puzzle list (5 items, ordered by difficulty)
- Arena link
- Brief WardLisp intro

### Screen 2: Puzzle (`/wardlisp/puzzle/:id`)
- Left: Code editor (textarea)
- Right: Test cases (visible inputs/expected)
- Bottom: Run button → result panel (HTMX swap)
- Result: pass/fail per test, fuel/cons/depth metrics, summary

### Screen 3: Arena (`/wardlisp/arena`)
- Left: Code editor (textarea for `decide-action`)
- Right: Grid display (HTML table, 7x7, icons for bot/enemy/wall/resource)
- Turn controls: prev/next/play buttons (minimal JS, hidden attribute toggle)
- Bottom: Turn log, final score, metrics

## 10. API Design

All endpoints return HTML (HTMX fragments for POST).

| Method | Path | Input | Output |
|--------|------|-------|--------|
| GET | `/wardlisp/` | - | Full page |
| GET | `/wardlisp/puzzle/:id` | - | Full page |
| POST | `/wardlisp/puzzle/:id/run` | `code` (form) | HTML fragment (#result-panel) |
| GET | `/wardlisp/arena` | - | Full page |
| POST | `/wardlisp/arena/run` | `code` (form) | HTML fragment (#arena-panel) |
| GET | `/wardlisp/reference` | - | Full page |

Arena response includes all 20 turn frames as hidden divs; JS toggles visibility.

## 11. Implementation Phases

### Phase 1: WardLisp Evaluator
**Goal**: Working evaluator with resource limits
**Done when**: REPL tests pass for arithmetic, lists, recursion, lambda, define, and all four limits

1. `wardlisp/types.lisp`
2. `wardlisp/reader.lisp` + tests
3. `wardlisp/environment.lisp` + tests
4. `wardlisp/builtins.lisp` + tests
5. `wardlisp/evaluator.lisp` + tests
6. Integration test: factorial with fuel limit

### Phase 2: Puzzle System
**Goal**: 5 puzzles solvable from browser
**Done when**: Browser → write code → run → see test results + metrics

1. `game/puzzle.lisp` + tests
2. `game/puzzles/*.lisp` (5 puzzle definitions)
3. `web/routes-wardlisp.lisp` (puzzle routes)
4. `web/ui/wardlisp-home.lisp`
5. `web/ui/puzzle.lisp`
6. Update `recurya.asd`
7. E2E: solve puzzle 1 in browser

### Phase 3: Arena System
**Goal**: Bot simulation with grid visualization
**Done when**: Write `decide-action` → run → see 20-turn grid replay

1. `game/arena.lisp` + tests
2. `game/scenario.lisp`
3. Enemy bot logic + tests
4. Arena routes in `web/routes-wardlisp.lisp`
5. `web/ui/arena.lisp` (grid + turn controls)
6. Minimal JS for turn stepping
7. E2E: greedy bot code → simulation completes

### Phase 4: Polish + Validation
**Goal**: MVP quality bar met
**Done when**: All acceptance criteria pass

1. Language reference page
2. Error message improvements
3. Limit-reached UX
4. Deterministic execution verification tests
5. Isolation verification tests
6. All Rove tests green

## 12. Acceptance Criteria

### Technical
- [ ] Reader rejects invalid input without CL errors
- [ ] Fuel limit stops infinite recursion
- [ ] Cons limit stops unbounded allocation
- [ ] Depth limit stops deep recursion
- [ ] Output limit stops infinite printing
- [ ] Deterministic: same program + same input → same result
- [ ] Bad code does not crash server
- [ ] 5 puzzles grade correctly
- [ ] 20-turn arena simulation completes
- [ ] All Rove tests pass

### User Experience
- [ ] Type code, press run, see results
- [ ] Test results show pass/fail clearly
- [ ] Resource usage (fuel/cons/depth) visible
- [ ] Errors produce readable messages
- [ ] Arena grid shows turn-by-turn replay
- [ ] Arena final score displayed

## 13. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Evaluator infinite loop | Server hang | Fuel limit is first thing implemented in Phase 1 |
| Accidental use of `cl:read` | Security hole | Custom reader from day 1; grep for `cl:read` in CI |
| Complex state representation | User confusion | Simple alist structure; rich reference examples |
| JS complexity for turn viz | Scope creep | Hidden-attribute toggle only; no animation |
| Test case bugs | Grading errors | 5+ test cases per puzzle including edge cases |
| Unfair enemy logic | Gameplay issues | Simple greedy algorithm; fairness is post-MVP |
| Puzzles 4-5 depend on Arena state | Ordering constraint | Build puzzles 1-3 first, add 4-5 after Arena state is defined |
| Spinneret grid rendering | Dev velocity | Simple HTML table; CSS-only styling |
