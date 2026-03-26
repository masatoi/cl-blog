# WardLisp External Library Migration Design

## Goal

Replace the in-house WardLisp interpreter (`wardlisp/` directory) with the external `masatoi/wardlisp` library already registered in `qlfile`. Motivation: the project was originally designed to use the external library.

## Architecture

Direct replacement — no adapter layer. Game and web layers call `wardlisp:evaluate` directly. All in-house wardlisp code is deleted.

## Key Differences: In-House vs External

| Aspect | In-House (delete) | External `masatoi/wardlisp` |
|--------|--------------------|-----------------------------|
| API | `(eval-program code :limits struct)` → `execution-result` struct | `(wardlisp:evaluate code &key fuel max-depth ...)` → `(values result metrics-plist)` |
| Booleans | `:true` / `:false` keywords | CL `t` / `nil` |
| Nil | `:wnil` keyword | CL `nil` |
| Lists | CL cons cells | `ocons` struct (`ocons-ocar`, `ocons-ocdr`) |
| TCO | No | Yes (trampoline) |
| Timeout | No | `sb-ext:with-timeout` |
| Integer overflow | No | `max-integer` limit |
| Display | `wardlisp->string` | `wardlisp:print-value` |
| Error types | `wardlisp-runtime-error`, `fuel-exhausted`, etc. | `wardlisp-error` hierarchy with parse/name/type/arity/limit subtypes |
| Special forms | quote, if, let, lambda, define, begin, and, or | + `cond`, `apply` |
| Division | `/` | `div` (integer division) |
| Builtins | `alist-ref` included | No `alist-ref` |

## Changes by Component

### 1. Delete: `wardlisp/` directory (5 files)

- `wardlisp/types.lisp`
- `wardlisp/environment.lisp`
- `wardlisp/reader.lisp`
- `wardlisp/builtins.lisp`
- `wardlisp/evaluator.lisp`

### 2. Delete: `tests/wardlisp/` directory (5 files)

- `tests/wardlisp/types.lisp`
- `tests/wardlisp/environment.lisp`
- `tests/wardlisp/reader.lisp`
- `tests/wardlisp/builtins.lisp`
- `tests/wardlisp/evaluator.lisp`

### 3. Rewrite: `game/puzzle.lisp`

- Replace `eval-program` + `execution-result` with `wardlisp:evaluate` + multiple values
- Result comparison: append `(equal? result expected)` to user code and check for `t`
- Display: `wardlisp:print-value` instead of `wardlisp->string`
- Remove all imports from `recurya/wardlisp/*`

### 4. Rewrite: `game/arena.lisp`

- Replace `eval-program` with `wardlisp:evaluate`
- State alist definition code remains the same (constructed inside WardLisp)
- Result keyword comparison (`:up`, `:down`, etc.) works as-is
- Remove all imports from `recurya/wardlisp/*`

### 5. Update: `game/puzzles/*.lisp`

- Change expected values: `:true`/`:false` → `t`/`nil`, `:wnil` → `nil`
- `choose-action.lisp`: remove `alist-ref` from injected code; add hint for users to define it themselves
- Remove all imports from `recurya/wardlisp/types`

### 6. Update: `web/routes-wardlisp.lisp`

- No structural changes (handlers call game layer, not wardlisp directly)

### 7. Update: `web/ui/puzzle.lisp`, `web/ui/arena.lisp`

- Result display: use `wardlisp:print-value` and metrics plist
- Error display: `(getf metrics :error-message)` instead of `execution-result-error`
- Output: `(getf metrics :output)` instead of `execution-result-output`

### 8. Update: `web/ui/reference.lisp`

- Booleans: `#t`/`#f` → `t`/`nil`
- Add: `div`, `cond`, `apply`, `atom?`, `eq?`
- Remove: `alist-ref`
- Update resource limit names to match external library

### 9. Update: `recurya.asd`

- Remove 5 `recurya/wardlisp/*` entries from `:depends-on`
- Add `"wardlisp"` as external dependency

### 10. Update: `tests/all.lisp`

- Remove 5 wardlisp test packages from `*test-packages*`
- Add integration test package

### 11. Create: `tests/wardlisp-integration.lisp`

Integration tests verifying external wardlisp works within recurya:
- Basic evaluate call
- Puzzle grading with external evaluator
- Arena simulation
- Resource limit enforcement

## Risks

- **`ocons` vs CL cons**: Any code that uses `consp`, `car`, `cdr` on wardlisp results needs to use `ocons-p`, `ocons-ocar`, `ocons-ocdr` instead.
- **`nil` ambiguity**: In external wardlisp, `nil` is both false and empty list (like Scheme). The in-house version distinguished them. This simplifies things.
- **No `alist-ref`**: The `choose-action` puzzle relied on this. Users must now define it themselves (educational opportunity).
