#!/usr/bin/env bash
# reseed.sh --- Restore the official (first-party) courses into the dev DB.
#
# Seeds the SICP and novel-lessons courses idempotently (safe to run
# repeatedly). Runs in a SEPARATE process inside the running `recurya`
# container via `docker compose exec`, so it uses its own DB connection and
# never disturbs the live web server's connection.
#
# The same seeder runs automatically at container boot
# (docker-entrypoint.sh); use this to restore official content on demand
# (e.g. after a fresh/empty database). Note: only the official content is
# seedable — courses/notebooks you created by hand in the UI are not part of
# the seed and cannot be restored this way.
#
# Usage (from anywhere; the app container must be up):
#   ./scripts/reseed.sh
set -euo pipefail
cd "$(dirname "$0")/.."

docker compose exec -T recurya \
  qlot exec ros run \
    -e '(load "scripts/seed-official-content.lisp")' \
    -q
