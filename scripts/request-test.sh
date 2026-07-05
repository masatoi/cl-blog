#!/usr/bin/env bash
# scripts/request-test.sh --- Browserless HTTP request tests for the MPA + HTMX UI.
#
# A "request test" (a.k.a. functional test at the HTTP layer, like Rails
# request specs / Django's test client): it drives the running app the same way
# the browser does -- through the HTTP request/response cycle -- but WITHOUT a
# browser. It replays HTMX requests exactly (session cookie + CSRF token +
# `HX-Request: true`) and asserts on the returned HTML, both full pages and HTMX
# fragments. It also checks "both sides" of an HTMX wiring: the trigger's
# hx-target AND that the target element's id actually exists in the page.
#
# What this CAN verify: server-rendered HTML, HTMX wiring/contract, returned
# fragments, routing, session, CSRF, auth, data flow, multi-step flows.
# What it CANNOT verify (needs a browser/eyes): client-side JS behaviour
# (CodeMirror, buttons) and visual/CSS/layout correctness.
#
# Usage (server must be up; see docs/DEVELOPMENT.md):
#   ./scripts/request-test.sh
# Override the base URL with RT_BASE=http://host:port ./scripts/request-test.sh
#
# To verify a specific UI change, copy one of the check blocks at the bottom:
#   - GET the changed page, assert the elements / hx-* wiring (+ target ids).
#   - If it has an HTMX action, replay it with rt_hx_post and assert the fragment.
set -uo pipefail
BASE="${RT_BASE:-http://localhost:13000}"
CJ="$(mktemp)"     # cookie jar (session)
BODY="$(mktemp)"   # last response body (page or fragment)
trap 'rm -f "$CJ" "$BODY"' EXIT

PASS=0; FAIL=0
_ok()  { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
_bad() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

# --- HTTP primitives ---------------------------------------------------------

rt_reset_session() { : > "$CJ"; }   # start a fresh anonymous session

# rt_get PATH -> writes body to $BODY, echoes the HTTP status code.
rt_get() { curl -s -c "$CJ" -b "$CJ" -o "$BODY" -w '%{http_code}' "$BASE$1"; }

# rt_login -> log in via the dev OAuth stub (OAUTH_DEV_STUB), keeping the
# session cookie. Only needed for pages behind auth.
rt_login() { curl -s -c "$CJ" -b "$CJ" -L -o /dev/null "$BASE/auth/google/start"; }

# rt_csrf -> extract the _csrf_token value from the last GET body ($BODY).
rt_csrf() {
  tr '\n' ' ' < "$BODY" \
    | grep -oE 'name=_csrf_token[^>]*value=[^ >]+' \
    | grep -oE 'value=[^ >]+' | head -1 | cut -d= -f2
}

# rt_hx_post PATH [key=value ...] -> replay an HTMX POST. Sends HX-Request,
# the session cookie, the CSRF token (from the last GET), and each key=value
# field (URL-encoded; repeat a key like codes[] to send multiple values).
# Writes the returned fragment to $BODY, echoes the status code.
rt_hx_post() {
  local url="$1"; shift
  local token; token="$(rt_csrf)"
  local args=(-s -c "$CJ" -b "$CJ" -o "$BODY" -w '%{http_code}'
              -H 'HX-Request: true' --data-urlencode "_csrf_token=$token")
  local kv
  for kv in "$@"; do args+=(--data-urlencode "$kv"); done
  curl "${args[@]}" "$BASE$url"
}

# --- assertions (all operate on $BODY unless noted) --------------------------

rt_status()       { [ "$1" = "$2" ] && _ok "$3 (status $2)" || _bad "$3 (want $1, got $2)"; }
rt_contains()     { grep -qF -- "$1" "$BODY" && _ok "$2" || _bad "$2 (missing: $1)"; }
rt_not_contains() { grep -qF -- "$1" "$BODY" && _bad "$2 (unexpected: $1)" || _ok "$2"; }

# =============================================================================
# Checks. Add/adapt blocks here when a UI change lands.
# Run only when executed directly; `source scripts/request-test.sh` in another
# script to reuse the primitives (rt_get/rt_login/rt_csrf/rt_hx_post/rt_*)
# without running these checks.
# =============================================================================
[ "${BASH_SOURCE[0]}" = "${0}" ] || return 0

echo "request-test against $BASE"

echo "[public] GET /notebooks"
rt_status 200 "$(rt_get /notebooks)" "public notebooks listing renders"

echo "[404] unknown @handle"
rt_status 404 "$(rt_get /@no-such-user-xyz-000)" "unknown handle -> 404"
rt_contains "404" "404 page shows 404"

echo "[notebook] HTMX wiring both-sides (SICP notebook, seeded)"
rt_status 200 "$(rt_get /@recurya/sicp-1-1-1)" "SICP notebook page renders"
rt_contains 'hx-post="/@recurya/sicp-1-1-1/cells/1/run"' "cell 1 Run wired to its run endpoint"
rt_contains '#cell-1-result' "cell 1 targets #cell-1-result"
rt_contains 'id=cell-1-result' "target #cell-1-result exists in the page (both-sides)"
rt_contains 'id=csrf-form' "csrf-form present for hx-include"

echo "[htmx] replay cell-run and assert the result fragment"
rt_get /@recurya/sicp-1-1-1 >/dev/null   # refresh: session cookie + CSRF token
rt_status 200 "$(rt_hx_post /@recurya/sicp-1-1-1/cells/1/run 'codes[]=' 'codes[]=(+ 137 349)')" \
  "cell-run HTMX endpoint returns 200"
rt_contains "result-ok" "run fragment renders a result panel"
rt_contains "486" "run fragment shows the evaluated value (137+349=486)"
rt_contains "Fuel:" "run fragment shows the resource metrics line"

echo
echo "=== request-test: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
