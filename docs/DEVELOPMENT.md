# Development workflow

This project runs entirely inside a long-lived Lisp image (the `recurya`
container). The web server, Swank (SLIME), and cl-mcp all share that one
image. The golden rule: **hot-reload code changes into the running image;
almost never restart the container.**

## Hot-reload (default for code changes)

A container restart drops the Swank/cl-mcp connection and the in-memory
state, and takes tens of seconds. For ordinary code edits you don't need it —
reload from a connected REPL (Emacs SLIME on `localhost:4005`, or the AI agent
via cl-mcp) instead:

```lisp
;; Reload one file after editing it:
(load "web/routes.lisp")

;; Reload a whole ASDF (sub)system, picking up all its changed files:
(asdf:load-system :recurya/web/routes :force t)

;; Reload everything:
(asdf:load-system :recurya :force t)
```

Routes are registered through a dynamic dispatch layer, so redefining a
handler takes effect on the next request with no server restart.

### When a container restart IS required

Only these need `docker compose build recurya && docker compose --profile app up -d`:

1. `Dockerfile` / `docker-compose.yml` changes
2. New Quicklisp dependencies (new entries in `qlfile` → `qlot install`)
3. ASDF system-structure changes (new modules, renamed packages/files)
4. Environment-variable changes

After a restart, reconnect cl-mcp / SLIME.

## Tests never touch your dev data

Tests run against a **dedicated `recurya_test` database**, created and
schema-applied automatically on first use. `tests/support/db:with-test-db`
binds the connection to `recurya_test` for the extent of each test, so the
running app's `recurya` connection is never touched, and
`cleanup-all-test-data` has a `current_database()` guard that refuses to run
against anything other than the test DB.

- Run a suite: `run-tests` (cl-mcp) or `(rove:run :recurya/tests/web/notebook-routes)`.
- Override the test DB name with `POSTGRES_TEST_DB` (default `recurya_test`).

> Historical note: before 2026-07-05, `with-test-db` cleaned the shared
> `recurya` connection, so running tests wiped all dev courses/notebooks.
> That is fixed — see `docs/superpowers/specs/2026-07-05-dev-workflow-data-protection-design.md`.

## Data persistence

- **Postgres data** lives in the named volume `postgres_data`. It survives
  `docker compose down` / `up` and container restarts. Only `docker compose
  down -v` deletes it.
- **Official content** (SICP, novel-lessons courses) is re-seeded idempotently
  at container boot. To restore it on demand (e.g. into a fresh DB), run:

  ```bash
  ./scripts/reseed.sh
  ```

  Courses/notebooks you created by hand in the UI are not part of the seed and
  cannot be auto-restored.
