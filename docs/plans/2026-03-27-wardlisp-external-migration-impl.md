# WardLisp External Library Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the in-house WardLisp interpreter with the external `masatoi/wardlisp` library (already in `qlfile`).

**Architecture:** Direct replacement — no adapter layer. Game and web layers call `wardlisp:evaluate` directly. All in-house WardLisp code is deleted.

**Tech Stack:** Common Lisp, ASDF package-inferred-system, Rove tests, Spinneret templates, HTMX

**Design Doc:** `docs/plans/2026-03-27-wardlisp-external-migration-design.md`

---

## API Mapping Quick Reference

| In-House | External |
|----------|----------|
| `(eval-program code :limits (make-execution-limits ...))` | `(wardlisp:evaluate code :fuel N :max-depth N :max-cons N :max-output N :timeout N)` |
| Returns `execution-result` struct | Returns `(values result metrics-plist)` |
| `(execution-result-value r)` | First return value |
| `(execution-result-error r)` | `(getf metrics :error-message)` |
| `(execution-result-fuel-used r)` | `(getf metrics :steps-used)` |
| `(execution-result-cons-used r)` | `(getf metrics :cons-allocated)` |
| `(execution-result-depth-reached r)` | `(getf metrics :max-depth-reached)` |
| `(execution-result-output r)` | `(getf metrics :output)` |
| `wardlisp-true` (`:true`) | `t` |
| `wardlisp-false` (`:false`) | `nil` |
| `wardlisp-nil` (`:wnil`) | `nil` |
| `(wardlisp-equal a b)` | `(wardlisp:print-value a)` string comparison (CL-side) |
| `(wardlisp->string val)` | `(wardlisp:print-value val)` |
| `make-execution-limits` | keyword args to `wardlisp:evaluate` |

---

### Task 1: Delete in-house wardlisp and update ASDF

**Files:**
- Delete: `wardlisp/types.lisp`, `wardlisp/environment.lisp`, `wardlisp/reader.lisp`, `wardlisp/builtins.lisp`, `wardlisp/evaluator.lisp`
- Delete: `tests/wardlisp/types.lisp`, `tests/wardlisp/environment.lisp`, `tests/wardlisp/reader.lisp`, `tests/wardlisp/builtins.lisp`, `tests/wardlisp/evaluator.lisp`
- Modify: `recurya.asd`
- Modify: `tests/all.lisp`

**Step 1: Delete the 10 files**

```bash
rm wardlisp/types.lisp wardlisp/environment.lisp wardlisp/reader.lisp \
   wardlisp/builtins.lisp wardlisp/evaluator.lisp
rm tests/wardlisp/types.lisp tests/wardlisp/environment.lisp \
   tests/wardlisp/reader.lisp tests/wardlisp/builtins.lisp \
   tests/wardlisp/evaluator.lisp
rmdir wardlisp/ tests/wardlisp/
```

**Step 2: Update `recurya.asd` main system**

Replace lines 23-28:
```lisp
               ;; WardLisp language
               "recurya/wardlisp/types"
               "recurya/wardlisp/environment"
               "recurya/wardlisp/reader"
               "recurya/wardlisp/builtins"
               "recurya/wardlisp/evaluator"
```
With:
```lisp
               ;; WardLisp language (external library)
               "wardlisp"
```

**Step 3: Update `recurya.asd` test system**

Replace lines 97-102:
```lisp
               ;; WardLisp tests
               "recurya/tests/wardlisp/types"
               "recurya/tests/wardlisp/environment"
               "recurya/tests/wardlisp/reader"
               "recurya/tests/wardlisp/builtins"
               "recurya/tests/wardlisp/evaluator"
```
With:
```lisp
               ;; WardLisp integration tests
               "recurya/tests/wardlisp-integration"
```

**Step 4: Update `tests/all.lisp`**

Replace the 5 wardlisp test packages:
```lisp
    :recurya/tests/wardlisp/types
    :recurya/tests/wardlisp/environment
    :recurya/tests/wardlisp/reader
    :recurya/tests/wardlisp/builtins
    :recurya/tests/wardlisp/evaluator
```
With:
```lisp
    :recurya/tests/wardlisp-integration
```

**Step 5: Commit**

```bash
git add -A && git commit -m "Delete in-house wardlisp, add external wardlisp dependency to ASDF"
```

---

### Task 2: Rewrite `game/puzzle.lisp` for external API

**Files:**
- Modify: `game/puzzle.lisp`

**Context:** The puzzle grader runs user code with test inputs and compares results. The in-house version used `wardlisp-equal` (CL-side comparison) and `execution-result-*` struct accessors. The external library returns `(values result metrics-plist)`. For comparison, use `wardlisp:print-value` to convert both expected and actual to strings (since `wardlisp-equal` is not exported from the external library).

**Step 1: Rewrite the package definition**

Replace the entire `defpackage` — remove all `recurya/wardlisp/*` imports:

```lisp
(defpackage #:recurya/game/puzzle
  (:use #:cl)
  (:import-from #:wardlisp
                #:evaluate
                #:print-value)
  (:export #:puzzle
           #:make-puzzle
           #:puzzle-id
           #:puzzle-title
           #:puzzle-description
           #:puzzle-signature
           #:puzzle-hint
           #:puzzle-test-cases
           #:puzzle-difficulty
           #:make-test-case
           #:test-case-input
           #:test-case-expected
           #:test-case-description
           #:run-puzzle
           #:puzzle-result
           #:puzzle-result-passed
           #:puzzle-result-failed
           #:puzzle-result-total
           #:puzzle-result-test-results
           #:puzzle-result-fuel-used
           #:puzzle-result-cons-used
           #:puzzle-result-depth-reached
           #:puzzle-result-error
           #:test-result
           #:test-result-passed-p
           #:test-result-expected
           #:test-result-actual
           #:test-result-description
           #:test-result-error))
```

**Step 2: Replace `*puzzle-limits*` parameter**

Replace:
```lisp
(defparameter *puzzle-limits*
  (make-execution-limits :fuel 10000 :max-cons 5000 :max-depth 100 :max-output 4096)
  "Default resource limits for puzzle execution.")
```
With:
```lisp
(defparameter *puzzle-fuel* 10000 "Default fuel limit for puzzle execution.")
(defparameter *puzzle-max-cons* 5000 "Default cons limit for puzzle execution.")
(defparameter *puzzle-max-depth* 100 "Default depth limit for puzzle execution.")
(defparameter *puzzle-max-output* 4096 "Default output limit for puzzle execution.")
(defparameter *puzzle-timeout* 5 "Default timeout in seconds for puzzle execution.")
```

**Step 3: Rewrite `run-puzzle`**

Replace the entire `run-puzzle` function:

```lisp
(defun run-puzzle (puzzle user-code)
  "Grade user code against puzzle test cases. Returns a puzzle-result."
  (let ((test-results nil)
        (total-fuel 0)
        (total-cons 0)
        (max-depth 0))
    (dolist (tc (puzzle-test-cases puzzle))
      (let ((full-code (format nil "~A~%~A" user-code (test-case-input tc))))
        (multiple-value-bind (result metrics)
            (evaluate full-code
                      :fuel *puzzle-fuel*
                      :max-cons *puzzle-max-cons*
                      :max-depth *puzzle-max-depth*
                      :max-output *puzzle-max-output*
                      :timeout *puzzle-timeout*)
          (incf total-fuel (getf metrics :steps-used))
          (incf total-cons (getf metrics :cons-allocated))
          (setf max-depth (max max-depth (getf metrics :max-depth-reached)))
          (if (getf metrics :error-message)
              (push (make-test-result
                     :passed-p nil
                     :expected (test-case-expected tc)
                     :actual nil
                     :description (test-case-description tc)
                     :error (getf metrics :error-message))
                    test-results)
              (let ((passed (string= (print-value result)
                                     (print-value (test-case-expected tc)))))
                (push (make-test-result
                       :passed-p passed
                       :expected (test-case-expected tc)
                       :actual result
                       :description (test-case-description tc))
                      test-results))))))
    (let ((results (nreverse test-results)))
      (make-puzzle-result
       :passed (count-if #'test-result-passed-p results)
       :failed (count-if-not #'test-result-passed-p results)
       :total (length results)
       :test-results results
       :fuel-used total-fuel
       :cons-used total-cons
       :depth-reached max-depth))))
```

**Step 4: Commit**

```bash
git add game/puzzle.lisp && git commit -m "Rewrite puzzle grader for external wardlisp API"
```

---

### Task 3: Update puzzle definitions for `t`/`nil` values

**Files:**
- Modify: `game/puzzles/adjacent.lisp`
- Modify: `game/puzzles/contains.lisp`
- Modify: `game/puzzles/nearest-point.lisp`
- Modify: `game/puzzles/safe-moves.lisp`
- Modify: `game/puzzles/choose-action.lisp`

**Context:** All puzzle files import `wardlisp-true`/`wardlisp-false`/`wardlisp-nil` from in-house types. Replace with CL `t`/`nil`. The `nearest-point` puzzle uses `(cons 1 (cons 0 wardlisp-nil))` for expected list values — replace with `'(1 0)` (regular CL list, since `print-value` comparison will match).

**Step 1: Fix `adjacent.lisp`**

Remove `:import-from #:recurya/wardlisp/types` entirely. Replace `wardlisp-true` → `t`, `wardlisp-false` → `nil`:

```lisp
(defpackage #:recurya/game/puzzles/adjacent
  (:use #:cl)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-adjacent-puzzle))
```

In `make-adjacent-puzzle`, all `:expected wardlisp-true` → `:expected t`, all `:expected wardlisp-false` → `:expected nil`.

**Step 2: Fix `contains.lisp`**

Same pattern as adjacent. Remove wardlisp/types import. `wardlisp-true` → `t`, `wardlisp-false` → `nil`.

**Step 3: Fix `safe-moves.lisp`**

Remove wardlisp/types import. `wardlisp-true` → `t`, `wardlisp-false` → `nil`. Note: `wardlisp-nil` is not used in expected values here; only `wardlisp-true`/`wardlisp-false` are.

**Step 4: Fix `nearest-point.lisp`**

Remove wardlisp/types import. Replace cons-chain expected values:
- `(cons 1 (cons 0 wardlisp-nil))` → `'(1 0)` (CL list — `print-value` comparison will match)
- `(cons 3 (cons 4 wardlisp-nil))` → `'(3 4)`

Note: The expected values are compared via `print-value` string comparison (from Task 2). `(print-value '(1 0))` won't work because CL lists are not ocons. We need to store expected values as strings for display and compare using the `print-value` output. **Alternative**: Store expected as the WardLisp source string of the expected value, run `wardlisp:evaluate` on it to get an ocons, and compare via `print-value`. But this is over-engineered. **Simplest**: Change `test-case-expected` to store the string representation for list-returning puzzles, and compare `print-value` of actual against the stored string. Actually, the cleanest approach: expected values that are integers/keywords/booleans (`t`/`nil`) can be compared with `print-value` on the CL side since `print-value` handles them. For list-expected-values, store the expected as a string like `"(1 0)"` and compare against `(print-value result)`.

**Revised approach for nearest-point.lisp expected values:**

```lisp
(make-test-case :input "(nearest '(0 0) '((1 0) (2 2) (0 3)))"
                :expected "(1 0)"
                :description "closest by Manhattan distance")
(make-test-case :input "(nearest '(3 3) '((0 0) (3 4) (5 5)))"
                :expected "(3 4)"
                :description "non-origin reference point")
(make-test-case :input "(nearest '(0 0) '((1 0)))"
                :expected "(1 0)"
                :description "single point in list")
```

And update the comparison logic in `run-puzzle` (Task 2) to handle expected values that are already strings:

```lisp
(let* ((actual-str (print-value result))
       (expected-str (if (stringp (test-case-expected tc))
                         (test-case-expected tc)
                         (print-value (test-case-expected tc))))
       (passed (string= actual-str expected-str)))
  ...)
```

**Update Task 2 Step 3** — The comparison in `run-puzzle` should use this enhanced logic.

**Step 5: Fix `choose-action.lisp`**

Remove wardlisp/types import (was importing `wardlisp-nil`, but it's not used in expected values — expected values are all keywords like `:down`, `:right`, etc.). Just remove the import:

```lisp
(defpackage #:recurya/game/puzzles/choose-action
  (:use #:cl)
  (:import-from #:recurya/game/puzzle #:make-puzzle #:make-test-case)
  (:export #:make-choose-action-puzzle))
```

No expected value changes needed — keywords work as-is with `print-value`.

**Step 6: Commit**

```bash
git add game/puzzles/ && git commit -m "Update puzzle expected values: t/nil, string-based list comparison"
```

---

### Task 4: Rewrite `game/arena.lisp` for external API

**Files:**
- Modify: `game/arena.lisp`

**Context:** The arena builds WardLisp source for game state, evaluates user code, and parses the returned action keyword. In-house imports: `eval-program`, `make-execution-limits`, `execution-result-*`, `wardlisp-nil`, `wardlisp-symbol-p`, `wardlisp->string`.

Key changes:
- `eval-program` → `wardlisp:evaluate` with `multiple-value-bind`
- `wardlisp-nil` → `nil` (used as list terminator in `grid->wardlisp-list` and `list->wardlisp-list`)
- `wardlisp-symbol-p` → not needed (action parsing uses `keywordp` which already works)
- `wardlisp->string` → `wardlisp:print-value` (used in error reporting)
- `*arena-limits*` → individual keyword args

**Step 1: Rewrite the package definition**

```lisp
(defpackage #:recurya/game/arena
  (:use #:cl)
  (:import-from #:wardlisp
                #:evaluate
                #:print-value)
  (:export #:arena-state
           #:make-arena-state
           #:arena-state-grid
           #:arena-state-bot-pos
           #:arena-state-enemy-pos
           #:arena-state-bot-score
           #:arena-state-enemy-score
           #:arena-state-turn
           #:arena-state-max-turns
           #:simulate-arena
           #:arena-result
           #:arena-result-frames
           #:arena-result-bot-score
           #:arena-result-enemy-score
           #:arena-result-fuel-used
           #:arena-result-error
           #:make-grid
           #:grid-set!
           #:grid-ref))
```

**Step 2: Replace `*arena-limits*`**

```lisp
(defparameter *arena-fuel* 5000 "Fuel limit per turn for arena evaluation.")
(defparameter *arena-max-cons* 2000 "Cons limit per turn for arena evaluation.")
(defparameter *arena-max-depth* 50 "Depth limit per turn for arena evaluation.")
(defparameter *arena-max-output* 1024 "Output limit per turn for arena evaluation.")
(defparameter *arena-timeout* 5 "Timeout in seconds per turn for arena evaluation.")
```

**Step 3: Fix `grid->wardlisp-list`**

This function builds cons-chain WardLisp lists with `wardlisp-nil` terminator. Since the arena generates WardLisp *source code* (not runtime values), this function is actually not needed — the state is communicated as WardLisp source text via `state->wardlisp-source`. Check if `grid->wardlisp-list` is used:

It is NOT called by `state->wardlisp-source` — the state is entirely generated as source text. `grid->wardlisp-list` and `list->wardlisp-list` appear to be unused. **Delete them.**

**Step 4: Rewrite `simulate-arena`**

Replace `eval-program` call with `wardlisp:evaluate` and `multiple-value-bind`:

```lisp
(defun simulate-arena (user-code initial-state)
  "Run a full arena simulation. Returns an arena-result."
  (let ((state (copy-state initial-state))
        (frames nil)
        (total-fuel 0))
    (push (copy-state state) frames)
    (handler-case
        (progn
          (dotimes (turn-num (arena-state-max-turns state))
            (setf (arena-state-turn state) (1+ turn-num))
            (let* ((state-source (state->wardlisp-source state))
                   (full-code (format nil "~A~%~A~%(decide-action state)"
                                      user-code state-source)))
              (multiple-value-bind (result metrics)
                  (evaluate full-code
                            :fuel *arena-fuel*
                            :max-cons *arena-max-cons*
                            :max-depth *arena-max-depth*
                            :max-output *arena-max-output*
                            :timeout *arena-timeout*)
                (incf total-fuel (getf metrics :steps-used))
                (when (getf metrics :error-message)
                  (return-from simulate-arena
                    (make-arena-result
                     :frames (nreverse frames)
                     :bot-score (arena-state-bot-score state)
                     :enemy-score (arena-state-enemy-score state)
                     :fuel-used total-fuel
                     :error (format nil "Turn ~D: ~A"
                                    (arena-state-turn state)
                                    (getf metrics :error-message)))))
                (let ((bot-action (parse-action result))
                      (enemy-action (enemy-decide-action
                                     (arena-state-enemy-pos state)
                                     (arena-state-grid state))))
                  ;; Apply bot movement
                  (unless (eq bot-action :pickup)
                    (setf (arena-state-bot-pos state)
                          (apply-move (arena-state-grid state)
                                      (arena-state-bot-pos state) bot-action)))
                  ;; Apply enemy movement
                  (unless (eq enemy-action :pickup)
                    (setf (arena-state-enemy-pos state)
                          (apply-move (arena-state-grid state)
                                      (arena-state-enemy-pos state) enemy-action)))
                  ;; Bot pickup first (priority)
                  (when (eq bot-action :pickup)
                    (when (try-pickup (arena-state-grid state)
                                      (arena-state-bot-pos state))
                      (incf (arena-state-bot-score state))))
                  ;; Enemy pickup second
                  (when (eq enemy-action :pickup)
                    (when (try-pickup (arena-state-grid state)
                                      (arena-state-enemy-pos state))
                      (incf (arena-state-enemy-score state))))
                  (push (copy-state state) frames)))))
          (make-arena-result
           :frames (nreverse frames)
           :bot-score (arena-state-bot-score state)
           :enemy-score (arena-state-enemy-score state)
           :fuel-used total-fuel))
      (error (e)
        (make-arena-result
         :frames (nreverse frames)
         :bot-score (arena-state-bot-score state)
         :enemy-score (arena-state-enemy-score state)
         :fuel-used total-fuel
         :error (format nil "Simulation error: ~A" e))))))
```

**Step 5: Commit**

```bash
git add game/arena.lisp && git commit -m "Rewrite arena simulator for external wardlisp API"
```

---

### Task 5: Update UI display functions

**Files:**
- Modify: `web/ui/puzzle.lisp`
- Modify: `web/ui/arena.lisp`

**Context:** The UI files import `wardlisp->string` from in-house types to display WardLisp values. Replace with `wardlisp:print-value`.

**Step 1: Update `web/ui/puzzle.lisp` package**

Replace:
```lisp
  (:import-from #:recurya/wardlisp/types
                #:wardlisp->string)
```
With:
```lisp
  (:import-from #:wardlisp
                #:print-value)
```

**Step 2: Update `render-result` in puzzle.lisp**

In `render-result`, replace the two calls to `wardlisp->string`:
```lisp
(format nil " expected ~A, got ~A"
        (wardlisp->string (test-result-expected tr))
        (wardlisp->string (test-result-actual tr)))
```
With:
```lisp
(format nil " expected ~A, got ~A"
        (print-value (test-result-expected tr))
        (print-value (test-result-actual tr)))
```

Note: `test-result-expected` may now be a string (for list-expected puzzles from Task 3). `print-value` on a CL string returns the string itself (it treats strings as symbol names). But for a CL string like `"(1 0)"`, `print-value` would return `"(1 0)"` which is correct for display. For `t`/`nil`/integers/keywords, `print-value` works correctly.

**Step 3: Update `web/ui/arena.lisp` package**

The arena UI imports from `recurya/game/arena` (for `arena-result-*`, `arena-state-*`, `render-grid`). Check if it imports `wardlisp->string`. Looking at the package:

```lisp
(:import-from #:recurya/wardlisp/types
              #:wardlisp->string)
```

If present, replace with `(:import-from #:wardlisp #:print-value)`. If not present, no change needed. (The collapsed view showed imports from game/arena only — let me check.)

Actually, looking at the arena UI render-result, it doesn't use `wardlisp->string` — it displays scores and grid states which are all native CL values. So likely no wardlisp type imports are needed. Remove any `recurya/wardlisp/*` imports if present.

**Step 4: Commit**

```bash
git add web/ui/puzzle.lisp web/ui/arena.lisp && git commit -m "Update UI display to use wardlisp:print-value"
```

---

### Task 6: Update language reference page

**Files:**
- Modify: `web/ui/reference.lisp`

**Context:** The reference page describes WardLisp language features. Update for external library differences.

**Step 1: Update Types table**

Change Boolean row: `#t` / `#f` → `t` / `nil`:
```lisp
(:tr (:td "Boolean") (:td (:code "t") ", " (:code "nil")) (:td "True and false"))
```

Change Nil row:
```lisp
(:tr (:td "Nil") (:td (:code "nil")) (:td "Empty list, false value"))
```

**Step 2: Add special forms**

Add `cond` and `apply` entries after `or`:

```lisp
(:div :class "entry"
 (:div :class "entry-sig" "(cond (test expr...)...)")
 (:div :class "entry-desc" "Multi-branch conditional. First true test's body is evaluated."))
(:div :class "entry"
 (:div :class "entry-sig" "(apply func args-list)")
 (:div :class "entry-desc" "Apply function to a list of arguments."))
```

**Step 3: Update Arithmetic section**

Change `(/ 10 2)` to `(div 10 2)` (integer division in external library):
```lisp
(:pre (:code "(+ 1 2 3)    ; => 6
(- 10 3)      ; => 7
(* 2 3 4)     ; => 24
(div 10 3)    ; => 3  (integer division)
(mod 7 3)     ; => 1
(abs -5)      ; => 5"))
```

**Step 4: Add type predicates**

Add `atom?` and `eq?`:
```lisp
(:pre (:code "(number? 42)    ; => t
(boolean? t)    ; => t
(symbol? :up)   ; => t
(list? '(1))    ; => t
(atom? 42)      ; => t
(eq? x y)       ; reference equality"))
```

**Step 5: Remove `alist-ref` from Utility section**

Replace:
```lisp
(:h3 "Utility")
(:pre (:code "(alist-ref :key '((:key . val) (:other . 2)))  ; => val"))
```
With:
```lisp
(:h3 "Utility")
(:pre (:code "(print 42)      ; prints to output
(equal? x y)    ; deep structural equality"))
```

**Step 6: Update Resource Limits table**

Update names and defaults to match external library:
```lisp
(:table :class "limit-table"
 (:tr (:th "Resource") (:th "Limit") (:th "Description"))
 (:tr (:td "Fuel") (:td "10,000 steps") (:td "Maximum evaluation steps"))
 (:tr (:td "Cons") (:td "5,000 cells") (:td "Maximum list allocations"))
 (:tr (:td "Depth") (:td "100 levels") (:td "Maximum recursion depth"))
 (:tr (:td "Output") (:td "4,096 bytes") (:td "Maximum printed output"))
 (:tr (:td "Timeout") (:td "5 seconds") (:td "Wall-clock time limit")))
```

**Step 7: Update `alist-ref` in working-with-alists example**

Replace:
```lisp
(:h3 "Working with alists")
(:pre (:code "(define state '((:pos . (3 4)) (:score . 5)))
(alist-ref :pos state)    ; => (3 4)
(alist-ref :score state)  ; => 5"))
```
With:
```lisp
(:h3 "Working with alists")
(:pre (:code ";; Define your own alist-ref helper:
(define (alist-ref key alist)
  (cond ((null? alist) nil)
        ((equal? key (car (car alist))) (cdr (car alist)))
        (t (alist-ref key (cdr alist)))))

(define state '((:pos 3 4) (:score . 5)))
(alist-ref :pos state)    ; => (3 4)
(alist-ref :score state)  ; => 5"))
```

**Step 8: Update boolean examples throughout**

Replace any remaining `#t`/`#f` in code examples with `t`/`nil`:
- `(if test then else)` description: "Only nil and '() are falsy" (already close to this)
- Comparison examples: `; => #t` → `; => t`
- Code examples should use `t`/`nil` consistently

**Step 9: Commit**

```bash
git add web/ui/reference.lisp && git commit -m "Update language reference for external wardlisp features"
```

---

### Task 7: Update game tests

**Files:**
- Modify: `tests/game/puzzle.lisp`
- Modify: `tests/game/arena.lisp`

**Context:** Game tests import from in-house wardlisp packages. Update imports and expected values.

**Step 1: Update `tests/game/puzzle.lisp`**

Remove the wardlisp/types import:
```lisp
  (:import-from #:recurya/wardlisp/types
                #:wardlisp-true
                #:wardlisp-false)
```

No expected value changes needed — the simple puzzle uses integers (6, 0, -10) which work as-is.

**Step 2: Update `tests/game/arena.lisp`**

The arena tests use `alist-ref` in WardLisp code within test strings. Since `alist-ref` is no longer a builtin, the test WardLisp code needs to define it or use an alternative.

Fix `wall-collision` test — the inline WardLisp code uses `(alist-ref :turn state)`. Replace with direct property access. Since `state` in the arena is an alist like `'((:turn . 1) ...)`, the code needs a way to access it. The simplest: prepend an `alist-ref` definition to the test code:

```lisp
(defparameter *alist-ref-def*
  "(define (alist-ref key alist)
     (cond ((null? alist) nil)
           ((equal? key (car (car alist))) (cdr (car alist)))
           (t (alist-ref key (cdr alist)))))")
```

Update tests that use `alist-ref` to prepend this definition:

```lisp
(deftest wall-collision
  (testing "bot stays when hitting wall"
    (let* ((arena (simple-arena))
           (result (simulate-arena
                    (format nil "~A~%(define (decide-action state)
                       (if (= (alist-ref :turn state) 1) :down :right))"
                            *alist-ref-def*)
                    arena))
           (frame2 (third (arena-result-frames result))))
      (ok (equal (cons 1 0) (arena-state-bot-pos frame2))))))
```

Similarly for `resource-pickup` test.

**Step 3: Commit**

```bash
git add tests/game/ && git commit -m "Update game tests for external wardlisp API"
```

---

### Task 8: Create integration test

**Files:**
- Create: `tests/wardlisp-integration.lisp`

**Step 1: Write the integration test file**

```lisp
;;;; tests/wardlisp-integration.lisp --- Integration tests for external wardlisp.

(defpackage #:recurya/tests/wardlisp-integration
  (:use #:cl #:rove)
  (:import-from #:wardlisp #:evaluate #:print-value))

(in-package #:recurya/tests/wardlisp-integration)

(deftest basic-evaluation
  (testing "arithmetic"
    (multiple-value-bind (result metrics) (evaluate "(+ 1 2)")
      (ok (= 3 result))
      (ok (null (getf metrics :error-message)))))

  (testing "booleans are t/nil"
    (ok (eq t (evaluate "(= 1 1)")))
    (ok (eq nil (evaluate "(= 1 2)")))))

(deftest resource-limits
  (testing "fuel exhaustion"
    (multiple-value-bind (result metrics)
        (evaluate "(define (loop) (loop)) (loop)" :fuel 50)
      (declare (ignore result))
      (ok (getf metrics :error-message))))

  (testing "depth limit"
    (multiple-value-bind (result metrics)
        (evaluate "(define (deep n) (deep (+ n 1))) (deep 0)" :max-depth 10)
      (declare (ignore result))
      (ok (getf metrics :error-message))))

  (testing "timeout"
    (multiple-value-bind (result metrics)
        (evaluate "(define (spin) (spin)) (spin)" :timeout 1)
      (declare (ignore result))
      (ok (getf metrics :error-message)))))

(deftest print-value-display
  (testing "integers"
    (ok (string= "42" (print-value 42))))
  (testing "booleans"
    (ok (string= "t" (print-value t)))
    (ok (string= "nil" (print-value nil))))
  (testing "keywords"
    (ok (string= ":up" (print-value :up)))))

(deftest puzzle-grading-integration
  (testing "correct puzzle solution grades properly"
    (let* ((puzzle (recurya/game/puzzle:make-puzzle
                    :id :test-double
                    :title "double"
                    :description "test"
                    :signature "(double x)"
                    :test-cases (list
                                 (recurya/game/puzzle:make-test-case
                                  :input "(double 3)" :expected 6
                                  :description "double 3"))))
           (result (recurya/game/puzzle:run-puzzle puzzle
                     "(define (double x) (* x 2))")))
      (ok (= 1 (recurya/game/puzzle:puzzle-result-passed result)))
      (ok (= 0 (recurya/game/puzzle:puzzle-result-failed result))))))

(deftest arena-integration
  (testing "arena simulation completes"
    (let ((result (recurya/game/arena:simulate-arena
                   "(define (decide-action state) :wait)"
                   (recurya/game/scenario:default-scenario))))
      (ok (null (recurya/game/arena:arena-result-error result))))))
```

**Step 2: Commit**

```bash
git add tests/wardlisp-integration.lisp && git commit -m "Add wardlisp integration tests"
```

---

### Task 9: Verify and fix — full test suite

**Step 1: Load system with clear-fasls**

```lisp
(load-system "recurya" :clear_fasls true)
```

**Step 2: Run all tests**

```lisp
(run-tests "recurya/tests")
```

**Step 3: Fix any failures**

Common issues to watch for:
- `print-value` on CL keyword returns `:up` (with colon) — verify arena `parse-action` still works since it checks `keywordp`
- `print-value` on `nil` returns `"nil"` — verify puzzle expected value comparison
- `ocons` vs CL cons in expected values — ensure no code tries `car`/`cdr` on `ocons`
- Missing `alist-ref` in arena test WardLisp code
- Package not found errors from stale ASDF cache

**Step 4: Run full test suite and verify all pass**

**Step 5: Commit any fixes**

```bash
git add -A && git commit -m "Fix test failures from wardlisp migration"
```

---

### Task 10: Clean up and final verification

**Step 1: Verify no remaining references to in-house wardlisp**

```bash
grep -r "recurya/wardlisp" --include="*.lisp" --include="*.asd" .
```

Should return zero matches.

**Step 2: Verify no remaining references to removed symbols**

```bash
grep -r "wardlisp-true\|wardlisp-false\|wardlisp-nil\|wardlisp->string\|wardlisp-equal\|eval-program\|execution-result\|execution-limits\|make-execution-limits" --include="*.lisp" .
```

Should return zero matches.

**Step 3: Verify external library loads**

```lisp
(ql:quickload :wardlisp)
(wardlisp:evaluate "(+ 1 2)")  ; => 3, (:steps-used N ...)
```

**Step 4: Final full test run**

```lisp
(run-tests "recurya/tests")
```

All tests must pass.

**Step 5: Commit if any cleanup was needed**

```bash
git add -A && git commit -m "Clean up remaining in-house wardlisp references"
```

---

## Summary of Changes

| Action | Files |
|--------|-------|
| **Delete** | 10 files (wardlisp/ + tests/wardlisp/) |
| **Rewrite** | game/puzzle.lisp, game/arena.lisp |
| **Update imports** | 5 puzzle defs, 2 UI files, 2 test files |
| **Update content** | web/ui/reference.lisp |
| **Create** | tests/wardlisp-integration.lisp |
| **Update config** | recurya.asd, tests/all.lisp |
| **Total commits** | ~8-10 |
