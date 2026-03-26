# Recurya

A Lisp learning game web system built with Common Lisp. Includes wardlisp, a safe server-side Lisp dialect for user code execution.

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
   POSTGRES_HOST=localhost POSTGRES_PORT=15434 POSTGRES_DB=recurya \
   POSTGRES_USER=postgres POSTGRES_PASSWORD=postgres \
   qlot exec ros run -e '(ql:quickload :recurya)' \
                     -e '(recurya/db/core:start!)' \
                     -e '(recurya/web/server:start!)'
   ```

4. **Open http://localhost:3000** in your browser.

5. **Stop PostgreSQL:**
   ```bash
   docker compose down      # Stop (data preserved)
   docker compose down -v   # Stop and remove data
   ```

## Running Tests

```bash
POSTGRES_HOST=localhost POSTGRES_PORT=15434 POSTGRES_DB=recurya \
POSTGRES_USER=postgres POSTGRES_PASSWORD=postgres \
qlot exec ros run \
  -e '(push (truename ".") asdf:*central-registry*)' \
  -e '(ql:quickload :recurya/tests)' \
  -e '(rove:run :recurya/tests)' \
  -q
```

## Database Migrations

This project uses the Mito CLI for schema migrations.

The Lisp system name is `:recurya`, so migration commands use `-s recurya`.

### Apply migrations (local)

```bash
.qlot/bin/mito migrate -t postgres -H localhost -P 15434 \
  -d recurya -u postgres -p postgres -s recurya -D db/
```

### Check migration status

```bash
.qlot/bin/mito migration-status -t postgres -H localhost -P 15434 \
  -d recurya -u postgres -p postgres -s recurya -D db/
```

### Generate a new migration

After editing `models/*.lisp`, generate migration files with:

```bash
.qlot/bin/mito generate-migrations -t postgres -H localhost -P 15434 \
  -d recurya -u postgres -p postgres -s recurya -D db/
```

Review the generated SQL before applying it.

## Project Structure

```
recurya/
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
| `POSTGRES_DB` | Database name (default: recurya) |
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
docker logs -f recurya

# Connect to Swank REPL (Emacs: M-x slime-connect → localhost:14005)

# Rebuild after Dockerfile/dependency changes
docker compose build recurya
docker compose --profile app up -d
```

## License

MIT
