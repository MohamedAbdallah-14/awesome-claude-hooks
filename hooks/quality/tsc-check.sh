#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   tsc-check
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .ts/.tsx file, runs `tsc --noEmit` in the
#              project root and compares the error count against the previously
#              cached count. If errors INCREASED, warns Claude about a
#              regression. If errors decreased or stayed the same, reports the
#              improvement (or clean state).
#
#              Cache file: /tmp/claude-tsc-{cwd-hash}.prev
#              The cache stores the integer error count from the last run.
#
#              Matches: .ts  .tsx
#
# Config (env vars):
#   CLAUDE_TSC_ARGS=""   Extra arguments passed to `tsc` (e.g. "--strict").
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
#               "command": "/path/to/hooks/quality/tsc-check.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[tsc-check] WARNING: jq not found — install it with: brew install jq" >&2
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
  *.ts|*.tsx) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── locate project root (walk up to find tsconfig.json) ──────────────────────

PROJECT_ROOT=""
SEARCH_DIR=$(dirname "$FILE_PATH")
while [[ "$SEARCH_DIR" != "/" ]]; do
  if [[ -f "$SEARCH_DIR/tsconfig.json" ]]; then
    PROJECT_ROOT="$SEARCH_DIR"
    break
  fi
  SEARCH_DIR=$(dirname "$SEARCH_DIR")
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "[tsc-check] WARNING: no tsconfig.json found in any parent of $FILE_PATH — skipping" >&2
  exit 0
fi

# ── tsc availability ──────────────────────────────────────────────────────────

TSC_BIN=""
if command -v tsc &>/dev/null; then
  TSC_BIN="tsc"
elif [[ -x "$PROJECT_ROOT/node_modules/.bin/tsc" ]]; then
  TSC_BIN="$PROJECT_ROOT/node_modules/.bin/tsc"
elif command -v npx &>/dev/null && npx --no-install tsc --version &>/dev/null 2>&1; then
  TSC_BIN="npx tsc"
fi

if [[ -z "$TSC_BIN" ]]; then
  echo "[tsc-check] WARNING: tsc not found — install TypeScript or run: npm install typescript" >&2
  exit 0
fi

# ── cache path based on project root hash ─────────────────────────────────────

CWD_HASH=$(printf '%s' "$PROJECT_ROOT" | md5sum 2>/dev/null | cut -c1-12 \
           || printf '%s' "$PROJECT_ROOT" | md5 2>/dev/null | cut -c1-12 \
           || printf '%s' "${#PROJECT_ROOT}")
CACHE_FILE="/tmp/claude-tsc-${CWD_HASH}.prev"

# ── run tsc --noEmit ──────────────────────────────────────────────────────────

TSC_EXTRA="${CLAUDE_TSC_ARGS:-}"

# Run from project root so tsc picks up tsconfig.json
TSC_OUTPUT=""
TSC_EXIT=0
# shellcheck disable=SC2086
TSC_OUTPUT=$(cd "$PROJECT_ROOT" && ${TSC_BIN} --noEmit ${TSC_EXTRA} 2>&1) || TSC_EXIT=$?

# Count lines matching "error TS" — each is one TypeScript error
CURRENT_ERRORS=$(printf '%s\n' "$TSC_OUTPUT" | grep -c "error TS" || true)

# ── compare against cached count ──────────────────────────────────────────────

PREV_ERRORS=-1
if [[ -f "$CACHE_FILE" ]]; then
  PREV_ERRORS=$(cat "$CACHE_FILE" 2>/dev/null || echo -1)
fi

# Update cache
printf '%s' "$CURRENT_ERRORS" > "$CACHE_FILE"

# ── report ────────────────────────────────────────────────────────────────────

if [[ "$CURRENT_ERRORS" -eq 0 ]]; then
  echo "[tsc-check] $FILE_PATH — TypeScript compiles clean (0 errors) in $PROJECT_ROOT"
  exit 0
fi

# Errors exist — determine if this is a regression
if [[ "$PREV_ERRORS" -ge 0 ]] && [[ "$CURRENT_ERRORS" -gt "$PREV_ERRORS" ]]; then
  DELTA=$(( CURRENT_ERRORS - PREV_ERRORS ))
  echo "[tsc-check] REGRESSION: TypeScript errors INCREASED by $DELTA in $PROJECT_ROOT"
  echo "[tsc-check]   Before this change: $PREV_ERRORS error(s)"
  echo "[tsc-check]   After this change:  $CURRENT_ERRORS error(s)"
elif [[ "$PREV_ERRORS" -ge 0 ]] && [[ "$CURRENT_ERRORS" -lt "$PREV_ERRORS" ]]; then
  DELTA=$(( PREV_ERRORS - CURRENT_ERRORS ))
  echo "[tsc-check] Improved: TypeScript errors decreased by $DELTA (was $PREV_ERRORS, now $CURRENT_ERRORS)"
else
  echo "[tsc-check] $CURRENT_ERRORS TypeScript error(s) in $PROJECT_ROOT (unchanged from before):"
fi

# Show the actual errors
echo ""
printf '%s\n' "$TSC_OUTPUT" | grep "error TS" | head -20
SHOWN=20
if [[ "$CURRENT_ERRORS" -gt "$SHOWN" ]]; then
  echo "  ... and $(( CURRENT_ERRORS - SHOWN )) more (run: cd $PROJECT_ROOT && ${TSC_BIN} --noEmit)"
fi

exit 0
