# Dev workflow: stop data loss and reduce restart friction

Date: 2026-07-05
Status: approved (interactive), implementation in progress

## Problem

The reported dev loop is painful: "every fix → container restart → re-login →
recreate notebooks/courses." Investigation split this into three independent
root causes:

1. **Data loss (the real culprit).** `tests/support/db.lisp`'s `with-test-db`
   calls `cleanup-all-test-data`, which runs unconditional
   `DELETE FROM course/notebook/course_notebook/novel_state/learn_*` and
   `DELETE FROM users WHERE email LIKE '%@example.com'` on the **global
   datasource** — the same connection the running web server uses, which points
   at the `recurya` (dev) database (`POSTGRES_DB=recurya`). There is **no**
   `recurya_test` database and **no** `current_database()` guard anywhere in
   the code. So **every `run-tests`/`with-test-db` wipes the dev DB's courses
   and notebooks.** (A prior memory claimed this was fixed via `recurya_test`
   separation on 2026-07-04; that fix does not exist in the code — the memory
   was wrong.)
2. **Re-login.** Lack `:session` middleware uses the default in-memory store, so
   sessions vanish on process/container restart.
3. **Unnecessary restarts.** The Postgres named volume `postgres_data` persists
   data across restart/`down`/`up` (only `down -v` wipes it). Per CLAUDE.md most
   code changes need only hot-reload, not a container restart.

## Decisions (approved)

Do all four, in order **① → ③ → ④ → ②**.

### ① Test DB isolation + hard guard (highest value)
- Tests run against a dedicated **`recurya_test`** database, created and
  schema-applied automatically (idempotent). Name configurable via
  `POSTGRES_TEST_DB` (default `recurya_test`).
- `db/core` gains: a raw connector to an arbitrary DB, a `with-connection`
  macro that dynamically binds the connection specials (`*datasource*` +
  Mito's `*connection*`) so tests never disturb the app's `recurya` connection,
  and `current-database`.
- `tests/support/db.lisp`: `with-test-db` connects to (a cached connection to)
  `recurya_test`; `cleanup-all-test-data` gains a **`current_database()`
  guard** that signals an error unless connected to the test DB — making it
  impossible to wipe `recurya` even by misuse.
- Schema applied by reading `db/schema.sql` (plain DDL, safe to split on `;`).
- Verify: full suite passes on `recurya_test`; a guard test proves cleanup
  aborts on a non-test DB.

### ③ One-command dev reseed (mostly exists)
- `recurya/seed/official-content:seed-official-content!` already exists and runs
  on container start (idempotent). Expose an on-demand, separate-process command
  (`scripts/reseed.sh`) to restore the official SICP / novel-lessons courses.
  User-created data is not recoverable (no backup).

### ④ Hot-reload recipe (docs)
- Document the "edit → reload without restart" recipe and the (few) cases that
  genuinely require a restart. Add a convenience entry point.

### ② Persistent session store — DB-backed (chosen for scale)
- Use Lack's bundled **`lack/middleware/session/store/dbi`**, which requires the
  `marshal` (cl-marshal) library — **not currently installed**. Add `marshal`
  to `qlfile`, `qlot install`, and rebuild the container **once** (user approved
  the one-time rebuild).
- Add a plain `sessions` table (`id`, `session_data`) to `db/schema.sql` (also
  picked up by `recurya_test`). Wire `:session :store (make-dbi-store ...)` into
  `build-app` with a connector using the app credentials.
- Sessions then survive restart; DB-backed store scales across instances.

## Non-goals
- No change to Mito `deftable` models. The `sessions` table is a plain table for
  Lack's store, not a Mito model.
- No connection pooling / horizontal-scale infra beyond the DB-backed store.
