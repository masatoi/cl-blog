---
description: Manage database schema changes with Mito CLI. Use when adding/modifying deftable definitions, running migrations, checking migration status, or resetting the development database.
argument-hint: [generate|apply|status|reset]
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, mcp__cl-mcp__repl-eval, mcp__cl-mcp__lisp-read-file, mcp__cl-mcp__clgrep-search
---

# Mito Migration Skill

Manage PostgreSQL schema changes via Mito CLI for this project.

## Arguments

`$ARGUMENTS` selects the operation:

- `/mito-migrate generate` - Generate migration from model changes
- `/mito-migrate apply` - Apply pending migrations
- `/mito-migrate status` - Check migration status
- `/mito-migrate reset` - Full database reset (development only)
- `/mito-migrate` (no args) - Detect what's needed and guide the user

## Connection Parameters

```
DB_HOST=localhost  DB_PORT=15434  DB_NAME=recurya
DB_USER=postgres   DB_PASS=postgres
ASDF_SYSTEM=recurya
MITO=.qlot/bin/mito
```

All CLI commands use:
```bash
.qlot/bin/mito <command> -t postgres -H localhost -P 15434 \
  -d recurya -u postgres -p postgres -s recurya -D db/
```

## Workflow by Operation

### generate

1. Confirm the user has already modified `deftable` in `models/*.lisp`
2. Run:
   ```bash
   .qlot/bin/mito generate-migrations -t postgres -H localhost -P 15434 \
     -d recurya -u postgres -p postgres -s recurya -D db/
   ```
3. Show the generated SQL (`db/migrations/YYYYMMDDHHMMSS.up.sql`) to the user for review
4. Ask if they want to apply immediately

### apply

1. Check status first to confirm there are pending migrations
2. Run:
   ```bash
   .qlot/bin/mito migrate -t postgres -H localhost -P 15434 \
     -d recurya -u postgres -p postgres -s recurya -D db/
   ```
3. Verify with status check after applying

### status

Run:
```bash
.qlot/bin/mito migration-status -t postgres -H localhost -P 15434 \
  -d recurya -u postgres -p postgres -s recurya -D db/
```

### reset (Development Only)

**IMPORTANT: Always confirm with the user before proceeding. This destroys all data.**

1. Stop the application container
2. Drop and recreate database:
   ```bash
   PGPASSWORD=postgres dropdb -h localhost -p 15434 -U postgres recurya
   PGPASSWORD=postgres createdb -h localhost -p 15434 -U postgres recurya
   ```
3. Optionally delete old migration files: `rm db/migrations/*.sql`
4. Generate initial migration from current models
5. Apply migration
6. Restart application container

## Verifying Schema Sync (REPL)

When the user wants to check if models match the database without running CLI:

```lisp
;; Returns NIL if schema matches, or list of needed changes
(mito:migration-expressions 'recurya/models/my-table:my-table)
```

## Mito Conventions

### deftable Rules
- **Foreign keys**: Reference by table class, not raw type (`:col-type dataset`, not `:col-type :uuid`)
- **Timestamps**: Omit `:record-timestamps` for automatic `created_at`/`updated_at`. Use `:timestamptz` for explicit columns.
- **Indexes**: `:unique-keys` for unique, `:keys` for non-unique. ASC/DESC not supported.
- **Primary keys**: UUID → `:auto-pk nil` + `:primary-key t` column. BIGSERIAL → omit id column.
- **FK constraints**: ON DELETE CASCADE etc. are NOT enforced by Mito; handle in application code.

### Important Notes
- Auto-migration is disabled (`mito:*auto-migration-mode*` is `nil`)
- Always run `mito migrate` before starting the application after model changes
- The `-s recurya` flag loads the ASDF system so Mito can find model definitions
- Migration files: `db/migrations/`
- Schema snapshot: `db/schema.sql`

## Troubleshooting

- **"relation already exists"**: Normal for `schema_migrations` table. Safe to ignore.
- **Migration not detected**: Ensure `-s recurya` is passed so models are loaded.
- **Schema drift after manual SQL**: Use the `reset` workflow to resync.
