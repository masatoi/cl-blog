# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Recurya is a Lisp learning game web system built with Common Lisp. Originally based on a blog template, it uses PostgreSQL (cl-dbi), Mito ORM, Ningle/Clack web framework, Spinneret HTML templates, and HTMX. It includes wardlisp, a safe server-side Lisp dialect for user code execution.

**Directory Structure:**
```
recurya/
├── models/     # Mito ORM table classes (deftable): users, post
├── db/         # Database layer: core, users, posts, jsonb
│   └── core.lisp  # Connection management
├── web/        # Web UI (Ningle + Spinneret)
│   ├── server.lisp   # Clack/Hunchentoot server start/stop
│   ├── app.lisp      # Ningle app + Lack middleware
│   ├── auth.lisp     # Session-based authentication
│   ├── routes.lisp   # Route handlers (auth, blog, account)
│   └── ui/           # Spinneret HTML templates
├── utils/      # Shared utilities
├── tests/      # Test suites (Rove)
└── prompts/    # AI agent guidelines
```

## For Common Lisp guideline

@prompts/common-lisp-expert.md
@prompts/repl-driven-development.md

## Special precautions when working with Lisp files

All Lisp operations go through cl-mcp tools as defined in `repl-driven-development.md`. This applies to **Claude Code's built-in tools as well** — do not use Read, Edit, Write, Grep, or Glob for `.lisp` / `.asd` files. Use `clgrep-search`, `lisp-read-file`, `lisp-edit-form`, `lisp-patch-form`, `repl-eval`, `load-system`, `run-tests` instead.

**Allowed shell commands**: `git`, `gh`, `mallet`, and user-requested commands only.

**First-time setup**: Call `fs-set-project-root` with `{"path": "."}` before file operations.

## Core Architecture

### Web Stack
- **Ningle** - Sinatra-like routing (`web/routes.lisp`)
- **Clack/Hunchentoot** - HTTP server (`web/server.lisp`)
- **Lack** - Middleware (session, backtrace) (`web/app.lisp`)
- **Spinneret** - Lisp-native HTML generation (`web/ui/*.lisp`)
- **HTMX** - Interactive UI without full page reloads (status toggle, delete)

### Authentication
Session-based auth with salted SHA-256 password hashing (`web/auth.lisp`). Lack session middleware.

### Database
- **Mito ORM** with `deftable` for model definitions
- **cl-dbi** for PostgreSQL connection
- Modular DB layer under `db/` (core, jsonb, users, posts)
- Auto-migration disabled; use Mito CLI

### Blog Features
- Multi-user post management with ownership checks
- Draft/published status toggle via HTMX
- Public blog with SEO-friendly slugs
- Pagination throughout

## Common Commands

### Development (with Docker Compose)
```bash
# Start PostgreSQL only
docker compose up -d

# Start PostgreSQL + app
docker compose --profile app up -d

# View logs
docker compose logs -f recurya

# Stop services
docker compose down      # preserves data
docker compose down -v   # removes data
```

### Database Access
```bash
psql postgresql://postgres:postgres@localhost:15434/recurya
```

### Running Tests
```bash
# Via Docker exec (inside container)
docker compose exec recurya qlot exec ros run \
  -e '(ql:quickload :recurya/tests)' \
  -e '(rove:run :recurya/tests/db/users)' -q
```

### Code Reload vs Container Restart (IMPORTANT)

**PREFER hot-reload over container restart.** Container restart disconnects cl-mcp/SLIME.

**Hot-Reload** (most code changes):
```lisp
(load "web/routes.lisp")
(asdf:load-system :recurya/web/routes :force t)
```

**Container Restart Required** only for:
1. Dockerfile / docker-compose.yml changes
2. New Quicklisp dependencies in .asd
3. ASDF system structure changes (new modules, renamed packages)
4. Environment variable changes

```bash
docker compose build recurya && docker compose --profile app up -d
```

> After container restart, cl-mcp/SLIME reconnection is needed.

## Database Operations

### IMPORTANT: Table Design Changes Require Confirmation

**Before modifying any `deftable` definitions, you MUST ask the user for confirmation.**

### Mito CLI Migrations

Use the `/mito-migrate` skill for migration operations. Quick reference:

```bash
.qlot/bin/mito migrate -t postgres -H localhost -P 15434 \
  -d recurya -u postgres -p postgres -s recurya -D db/
```

## Configuration

### Environment Variables
| Variable | Description |
|----------|-------------|
| `POSTGRES_HOST` | PostgreSQL host (default: localhost) |
| `POSTGRES_PORT` | PostgreSQL port (default: 5432) |
| `POSTGRES_DB` | Database name (default: recurya) |
| `POSTGRES_USER` | Database user (default: postgres) |
| `POSTGRES_PASSWORD` | Database password |
| `PORT` | HTTP server port (default: 3000) |

### Docker Compose Ports
| Port | Service |
|------|---------|
| 3000 | Web server (Ningle/Hunchentoot) |
| 15434 | PostgreSQL |
| 14005 | Swank (Emacs SLIME) |
| 12346 | cl-mcp HTTP (AI agent) |

## Key Conventions

- **Package-inferred system**: Package names must match file paths (e.g., `recurya/db/users` for `db/users.lisp`)
- **Mito ORM**: Use `deftable` for model definitions, singular table names
- **cl-dbi quirk**: NIL converts to string "false" in PostgreSQL; use `:null` for SQL NULL
- **Helper functions**: `nil->null` (write), `null->nil` (read) for PostgreSQL NULL handling
- **Timestamps**: Use `local-time:now` for creation, format with ISO-8601 for database
- **Testing**: Rove framework with `:style :spec`

## cl-mcp Feedback

When you encounter issues, friction, or improvement ideas while using cl-mcp (Common Lisp MCP server), append them to `~/.claude/memory/cl-mcp-feedback.md`. Each entry should include date, context, and specific details. If the file already exists, always append to the end rather than overwriting.
