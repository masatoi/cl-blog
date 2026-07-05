# Development workflow

This project runs inside the long-lived `recurya` container. cl-mcp's worker
pool is enabled and the **web server runs inside the cl-mcp worker** for your
session (started by the worker-init hook), co-located with your
repl-eval/load-system. The golden rule: **hot-reload code changes into the
running worker; almost never restart the container.**

## Hot-reload (default for code changes)

For ordinary code edits, reload from a connected REPL (the AI agent via cl-mcp,
or Emacs SLIME on `localhost:4005`) instead of restarting anything:

```lisp
;; Reload one file after editing it:
(load "web/routes.lisp")

;; Reload a whole ASDF (sub)system, picking up all its changed files:
(asdf:load-system :recurya/web/routes :force t)

;; Reload everything:
(asdf:load-system :recurya :force t)
```

Because the web server lives in your cl-mcp worker, `load-system` lands in the
same process as the running server, so the change is live on the next request.
Routes use a dynamic dispatch layer, so a redefined handler takes effect
immediately with no server restart.

### Full runtime reset (fresh Lisp process, no reconnect)

To throw away all in-memory state and get a clean Lisp process for the app, use
cl-mcp's `pool-kill-worker` (reset). It kills your worker (and the web server in
it) and spawns a fresh one, which re-runs the init hook and restarts the web
server in ~3s. The cl-mcp parent survives, so **no `/mcp` reconnect is needed**.

### When a full container recreate IS required

Only these need a recreate
(`docker compose --profile app up -d --force-recreate recurya`; deps are
volume-mounted, so an image rebuild is only needed for `Dockerfile` changes):

1. `Dockerfile` / `docker-compose.yml` changes
2. New Quicklisp dependencies (new `qlfile` entries → `qlot install`)
3. ASDF system-structure changes (new modules, renamed packages/files)
4. Environment-variable changes

A recreate drops the cl-mcp parent, so reconnect with `/mcp` afterwards — the
only time a reconnect is needed. The app comes back up when your next MCP
session's worker is elected runtime owner.

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
- **Login sessions** are stored in the Postgres `sessions` table (Lack's
  DBI session store, wired in `web/server.lisp`), so you stay logged in
  across a server/container restart. The table is created automatically at
  server start (`ensure-sessions-table!`).
- **Official content** (SICP, novel-lessons courses) is re-seeded idempotently
  at container boot. To restore it on demand (e.g. into a fresh DB), run:

  ```bash
  ./scripts/reseed.sh
  ```

  Courses/notebooks you created by hand in the UI are not part of the seed and
  cannot be auto-restored.

## Verifying UI changes without a browser

This is an MPA + HTMX app: the server renders both full pages and the HTML
fragments that HTMX swaps in, so **most UI verification can be done server-side,
no browser required.** Two levels:

1. **Handler / render tests (Rove).** Call the handler with a mock
   session/params and assert on the returned HTML — elements, `hx-*` wiring, and
   fragment content. This is what `tests/web/*.lisp` already do (e.g. asserting
   `hx-post=...`, `class="sb-link active"`, or a run fragment's body). Run with
   `run-tests` / `(rove:run :recurya/tests/web/notebook-routes)`.

2. **HTTP smoke against the live server:** `./scripts/smoke.sh`. It drives the
   running server over HTTP and replays HTMX requests exactly as the browser
   would (session cookie + CSRF token + `HX-Request: true`), asserting on pages
   and fragments. Use it after a UI change; copy a check block for whatever
   you changed.

**Check both sides of an HTMX wiring.** When asserting an interaction, check the
trigger's `hx-target="#foo"` AND that an element with `id=foo` exists in the
page, plus the replayed fragment. That closes the trigger → target → fragment
loop server-side; HTMX-in-the-browser applying it is safe to trust. If a change
renames an `id`/`class`/selector that JS or `hx-include`/`hx-target` depends on,
add an assertion for it.

**What still needs a browser or eyes** (a small residual): client-side JS
behaviour (CodeMirror editor, buttons, arena stepping, novel advance) — cover
its logic with the `node` tests, and visual/CSS/layout correctness — a quick
human glance. Everything else is server-side.
