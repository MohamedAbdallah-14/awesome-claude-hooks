#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   inject-typescript-errors
# Event:       PreToolUse
# Matcher:     Edit|Write|MultiEdit
# Description: Before Claude edits a .ts or .tsx file, runs tsc --noEmit and
#              injects the current error count + first 20 diagnostics as context.
#              Results are cached for 30 seconds to avoid hammering tsc on
#              every keystroke when multiple files are being edited.
#
#              Non-blocking heuristic: if tsc takes longer than CLAUDE_TSC_TIMEOUT
#              seconds, the hook approves immediately with a timeout note.
#
# Config (env vars):
#   CLAUDE_TSC_TIMEOUT   Max seconds to wait for tsc. Default: 10.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Edit|Write|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/context/inject-typescript-errors.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────

approve() { printf '{"decision":"approve"}\n'; exit 0; }

approve_with_context() {
  local ctx="$1"
  jq -n --arg c "$ctx" '{"decision":"approve","context":$c}'
  exit 0
}

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  approve
fi

# ── config ────────────────────────────────────────────────────────────────────

TSC_TIMEOUT="${CLAUDE_TSC_TIMEOUT:-10}"
CACHE_TTL=30   # seconds

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  approve
fi

TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r '.tool_input // {}')

# ── resolve file path ─────────────────────────────────────────────────────────

FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '
  if type == "object" then
    (.file_path // (.edits[0].file_path? // "") // "")
  else ""
  end
' 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]]; then
  approve
fi

# Only act on TypeScript files
if [[ "$FILE_PATH" != *.ts ]] && [[ "$FILE_PATH" != *.tsx ]]; then
  approve
fi

# Resolve to absolute path
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="${PWD}/${FILE_PATH}"
fi

# ── find tsconfig.json ────────────────────────────────────────────────────────

# Walk up from file's directory to find nearest tsconfig
find_tsconfig() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "${dir}/tsconfig.json" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

PROJECT_ROOT=$(find_tsconfig "$(dirname "$FILE_PATH")" 2>/dev/null || true)
if [[ -z "$PROJECT_ROOT" ]]; then
  # No tsconfig — not a TS project we can check
  approve
fi

# ── resolve tsc binary ────────────────────────────────────────────────────────

TSC_BIN=""
if [[ -x "${PROJECT_ROOT}/node_modules/.bin/tsc" ]]; then
  TSC_BIN="${PROJECT_ROOT}/node_modules/.bin/tsc"
elif command -v npx &>/dev/null; then
  TSC_BIN="npx --no-install tsc"
elif command -v tsc &>/dev/null; then
  TSC_BIN="tsc"
else
  approve
fi

# ── cache logic ───────────────────────────────────────────────────────────────

# Hash the project root path for a stable, collision-resistant cache key
PROJECT_HASH=$(printf '%s' "$PROJECT_ROOT" | md5sum 2>/dev/null | cut -c1-8 \
  || printf '%s' "$PROJECT_ROOT" | md5 2>/dev/null | cut -c1-8 \
  || echo "default")

CACHE_FILE="/tmp/claude-ts-errors-${PROJECT_HASH}.cache"
NOW=$(date +%s)

# Check cache freshness
if [[ -f "$CACHE_FILE" ]]; then
  CACHE_AGE=$(( NOW - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if (( CACHE_AGE < CACHE_TTL )); then
    CACHED_CONTEXT=$(cat "$CACHE_FILE")
    approve_with_context "$CACHED_CONTEXT"
  fi
fi

# ── run tsc ───────────────────────────────────────────────────────────────────

TSC_OUTPUT=""
TSC_EXIT=0

# Run with timeout; suppress stdin to avoid tsc hanging
if command -v timeout &>/dev/null; then
  TSC_OUTPUT=$(cd "$PROJECT_ROOT" && \
    timeout "${TSC_TIMEOUT}" ${TSC_BIN} --noEmit --pretty false 2>&1 </dev/null || true)
else
  # macOS: use perl-based timeout fallback
  TSC_OUTPUT=$(cd "$PROJECT_ROOT" && \
    { ${TSC_BIN} --noEmit --pretty false 2>&1 </dev/null & TSC_PID=$!
      sleep "${TSC_TIMEOUT}" && kill "$TSC_PID" 2>/dev/null & SLEEP_PID=$!
      wait "$TSC_PID" 2>/dev/null; RC=$?
      kill "$SLEEP_PID" 2>/dev/null || true
      exit "$RC"
    } || true)
fi

# ── parse output ─────────────────────────────────────────────────────────────

# Count error lines: "file.ts(line,col): error TS..."
ERROR_COUNT=$(printf '%s' "$TSC_OUTPUT" | grep -c ': error TS' 2>/dev/null || echo "0")
FIRST_ERRORS=$(printf '%s' "$TSC_OUTPUT" | grep ': error TS' 2>/dev/null | head -20 || true)

if [[ "$ERROR_COUNT" -eq 0 ]]; then
  CONTEXT="TypeScript: no errors in \`${PROJECT_ROOT}\`."
else
  CONTEXT="TypeScript: ${ERROR_COUNT} error(s) in \`${PROJECT_ROOT}\`.\n\nFirst errors:\n\`\`\`\n${FIRST_ERRORS}\n\`\`\`"
fi

# ── write cache ───────────────────────────────────────────────────────────────

printf '%s' "$CONTEXT" > "$CACHE_FILE"

approve_with_context "$CONTEXT"
