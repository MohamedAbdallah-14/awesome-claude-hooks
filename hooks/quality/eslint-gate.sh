#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   eslint-gate
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a JS/TS file, runs ESLint and reports any
#              errors or warnings so Claude can immediately see and fix them.
#              Does NOT block — reports results as informational output.
#
#              Matches: .js  .jsx  .ts  .tsx
#
# Config (env vars):
#   CLAUDE_ESLINT_CONFIG=path    Path to ESLint config file (optional; ESLint
#                                will auto-discover if not set).
#   CLAUDE_ESLINT_MAX_WARNINGS=0 Treat warnings as errors if count exceeds this
#                                value. Default 0 (any warning is reported).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Write|Edit|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/quality/eslint-gate.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[eslint-gate] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── extension filter ──────────────────────────────────────────────────────────

case "$FILE_PATH" in
  *.js|*.jsx|*.ts|*.tsx) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── eslint availability ───────────────────────────────────────────────────────

ESLINT_BIN=""
if command -v eslint &>/dev/null; then
  ESLINT_BIN="eslint"
elif [[ -x "$(dirname "$FILE_PATH")/node_modules/.bin/eslint" ]]; then
  ESLINT_BIN="$(dirname "$FILE_PATH")/node_modules/.bin/eslint"
elif command -v npx &>/dev/null && npx --no-install eslint --version &>/dev/null 2>&1; then
  ESLINT_BIN="npx eslint"
fi

if [[ -z "$ESLINT_BIN" ]]; then
  echo "[eslint-gate] WARNING: eslint not found — skipping lint check for $FILE_PATH" >&2
  exit 0
fi

# ── build eslint args ─────────────────────────────────────────────────────────

MAX_WARNINGS="${CLAUDE_ESLINT_MAX_WARNINGS:-0}"
ESLINT_ARGS=("--format" "compact" "--max-warnings" "$MAX_WARNINGS")

if [[ -n "${CLAUDE_ESLINT_CONFIG:-}" ]]; then
  ESLINT_ARGS+=("--config" "$CLAUDE_ESLINT_CONFIG")
fi

# ── run eslint ────────────────────────────────────────────────────────────────

ESLINT_OUTPUT=""
ESLINT_EXIT=0
ESLINT_OUTPUT=$(${ESLINT_BIN} "${ESLINT_ARGS[@]}" "$FILE_PATH" 2>&1) || ESLINT_EXIT=$?

# ── report results ────────────────────────────────────────────────────────────

if [[ $ESLINT_EXIT -eq 0 ]]; then
  echo "[eslint-gate] $FILE_PATH — no ESLint issues found"
else
  echo "[eslint-gate] ESLint found issues in $FILE_PATH:"
  echo "$ESLINT_OUTPUT"
  echo ""
  echo "[eslint-gate] Fix the issues above, or run: ${ESLINT_BIN} --fix $FILE_PATH"
fi

exit 0
