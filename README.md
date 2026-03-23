# cl-blog

A simple blog system built with Common Lisp, intended as a reusable template for HTMX-powered responsive MPAs.

## Prerequisites

- [Roswell](https://github.com/roswell/roswell) (Common Lisp environment manager)
- [qlot](https://github.com/fukamachi/qlot) (`ros install qlot`)
- Docker and Docker Compose (for PostgreSQL)

## Quick Start

1. **Install dependencies:**
   ```bash
   qlot install
   ```

2. **Start PostgreSQL:**
   ```bash
   docker compose up -d
   ```

3. **Run the application:**
   ```bash
   POSTGRES_HOST=localhost POSTGRES_PORT=15434 POSTGRES_DB=cl_blog \
   POSTGRES_USER=postgres POSTGRES_PASSWORD=postgres \
   qlot exec ros run -e '(ql:quickload :cl-blog)' \
                     -e '(cl-blog/db/core:start!)' \
                     -e '(cl-blog/web/server:start!)'
   ```

4. **Open http://localhost:3000** in your browser.

5. **Stop PostgreSQL:**
   ```bash
   docker compose down      # Stop (data preserved)
   docker compose down -v   # Stop and remove data
   ```

## Running Tests

```bash
POSTGRES_HOST=localhost POSTGRES_PORT=15434 POSTGRES_DB=cl_blog \
POSTGRES_USER=postgres POSTGRES_PASSWORD=postgres \
qlot exec ros run \
  -e '(push (truename ".") asdf:*central-registry*)' \
  -e '(ql:quickload :cl-blog/tests)' \
  -e '(rove:run :cl-blog/tests)' \
  -q
```

## Database Migrations

This project uses the Mito CLI for schema migrations.

The current Lisp system name is still `:cl-blog`, so migration commands use `-s cl-blog`.

### Apply migrations (local)

```bash
.qlot/bin/mito migrate -t postgres -H localhost -P 15434 \
  -d cl_blog -u postgres -p postgres -s cl-blog -D db/
```

### Check migration status

```bash
.qlot/bin/mito migration-status -t postgres -H localhost -P 15434 \
  -d cl_blog -u postgres -p postgres -s cl-blog -D db/
```

### Generate a new migration

After editing `models/*.lisp`, generate migration files with:

```bash
.qlot/bin/mito generate-migrations -t postgres -H localhost -P 15434 \
  -d cl_blog -u postgres -p postgres -s cl-blog -D db/
```

Review the generated SQL before applying it.

## Project Structure

```
cl-blog/
├── models/     # Mito ORM table definitions (users, post)
├── db/         # Database layer (core, jsonb, users, posts)
├── utils/      # Shared utilities
├── web/        # Web UI (Ningle + Spinneret)
│   ├── server.lisp   # Clack/Hunchentoot server
│   ├── app.lisp      # Ningle app + Lack middleware
│   ├── auth.lisp     # Session-based authentication
│   ├── routes.lisp   # Route handlers
│   └── ui/           # Spinneret HTML templates
└── tests/      # Test suites (Rove)
```

## Configuration

| Variable | Description |
|----------|-------------|
| `POSTGRES_HOST` | PostgreSQL host (default: localhost) |
| `POSTGRES_PORT` | PostgreSQL port (default: 5432) |
| `POSTGRES_DB` | Database name (default: cl_blog) |
| `POSTGRES_USER` | Database user (default: postgres) |
| `POSTGRES_PASSWORD` | Database password |
| `PORT` | HTTP server port (default: 3000) |

### cl-mcp Development Server

When running through Docker Compose, `cl-mcp` is started in HTTP server mode on port `12346`.

Endpoint: `http://localhost:12346/mcp`

## Development with Docker

```bash
# Start PostgreSQL + CL runtime
docker compose --profile app up -d

# View logs
docker logs -f cl-blog

# Connect to Swank REPL (Emacs: M-x slime-connect → localhost:14005)

# Rebuild after Dockerfile/dependency changes
docker compose build cl-blog
docker compose --profile app up -d
```

## License

MIT
