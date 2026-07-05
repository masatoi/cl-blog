#!/bin/bash
# Entrypoint script for recurya development
# Ensures proper output flushing for Docker logs
#
# Working directory is set externally:
#   - Development: ${PWD} (via docker-compose working_dir)
#   - Production: /app (via Dockerfile WORKDIR)
#
# Services started in this (parent) process:
#   - Swank server on port 4005 (for Emacs SLIME connection)
#   - cl-mcp HTTP server on port 12346 (for AI agent connection); worker pool
#     enabled, so repl-eval/load-system run in a per-session worker process.
# The web server (port 13000) is NOT started here. It is started inside the
# cl-mcp worker via the worker-init hook (MCP_WORKER_INIT_* in compose), so a
# runtime reset (pool-kill-worker) restarts the app without dropping cl-mcp.
# The DB is seeded here at boot so official content exists before any worker.

set -e

echo "Starting recurya development environment..."
echo "Working directory: $(pwd)"
echo "Environment: POSTGRES_HOST=$POSTGRES_HOST POSTGRES_PORT=$POSTGRES_PORT POSTGRES_DB=$POSTGRES_DB"

# Set up qlot dependencies
# In development mode (not /app), we use the pre-installed deps from the image
if [ ! -f ".qlot/setup.lisp" ]; then
    if [ "$(pwd)" != "/app" ] && [ -f "/app/.qlot/setup.lisp" ]; then
        echo "Linking to pre-installed qlot dependencies from /app/.qlot..."
        ln -sf /app/.qlot .qlot
    else
        echo "Installing qlot dependencies (first run)..."
        qlot install
    fi
fi

exec qlot exec ros run \
    --eval "(setf sb-impl::*default-external-format* :utf-8)" \
    --eval "(ql:quickload :recurya)" \
    --eval "(format t \"~%ASDF system :recurya loaded successfully.~%\")" \
    --eval "(force-output)" \
    --eval "(ql:quickload :swank)" \
    --eval "(setf swank:*communication-style* :spawn)" \
    --eval "(swank:create-server :port 4005 :dont-close t :interface \"0.0.0.0\")" \
    --eval "(format t \"~%Swank server started on port 4005~%\")" \
    --eval "(force-output)" \
    --eval "(recurya/db/core:start!)" \
    --eval "(format t \"Database connection established~%\")" \
    --eval "(force-output)" \
    --eval "(handler-case (progn (recurya/seed/official-content:seed-official-content!) (format t \"Official content seeded~%\")) (error (e) (format t \"~&[seed] WARN: ~A~%\" e)))" \
    --eval "(force-output)" \
    --eval "(ql:quickload :cl-mcp)" \
    --eval "(mcp:start-http-server :port 12346 :host \"0.0.0.0\")" \
    --eval "(format t \"cl-mcp HTTP server started on port 12346~%\")" \
    --eval "(force-output)" \
    --eval "(format t \"~%=== recurya development environment ready ===\")" \
    --eval "(format t \"~%  Web: http://localhost:13000 (started in the cl-mcp worker on first MCP session)\")" \
    --eval "(format t \"~%  Swank: localhost:4005 (M-x slime-connect)\")" \
    --eval "(format t \"~%  cl-mcp HTTP: http://localhost:12346/mcp\")" \
    --eval "(format t \"~%  web server + repl-eval/load-system run in the worker; reset via pool-kill-worker~%\")" \
    --eval "(force-output)" \
    --eval "(loop (sleep 60))"
