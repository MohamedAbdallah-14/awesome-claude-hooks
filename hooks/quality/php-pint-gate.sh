#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   php-pint-gate
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .php file, runs Laravel Pint in --test
#              mode (vendor/bin/pint --test <file>). When Pint isn't vendored,
#              falls back to `php -l <file>` for a syntax-only check. Blocks
#              the change with a deny decision on style or syntax issues.
#              Silently skips when neither Pint nor php is available.
#
#              Matches: .php
#
# Config (env vars):
#   CLAUDE_PHP_PINT_GATE_SKIP=1   Skip this gate entirely (silent pass). Default: gate enforced.
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
#               "command": "/path/to/hooks/quality/php-pint-gate.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── bypass switch ─────────────────────────────────────────────────────────────

if [[ "${CLAUDE_PHP_PINT_GATE_SKIP:-0}" == "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[php-pint-gate] WARNING: jq not found — install it with: brew install jq" >&2
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
  *.php) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── tool selection: prefer vendored Pint, fall back to php -l ────────────────

CHECK_OUTPUT=""
CHECK_EXIT=0
TOOL_USED=""

if [[ -x "vendor/bin/pint" ]]; then
  TOOL_USED="pint"
  CHECK_OUTPUT=$(vendor/bin/pint --test "$FILE_PATH" 2>&1) || CHECK_EXIT=$?
elif command -v pint &>/dev/null; then
  TOOL_USED="pint"
  CHECK_OUTPUT=$(pint --test "$FILE_PATH" 2>&1) || CHECK_EXIT=$?
elif command -v php &>/dev/null; then
  TOOL_USED="php-l"
  CHECK_OUTPUT=$(php -l "$FILE_PATH" 2>&1) || CHECK_EXIT=$?
else
  # Nothing available — silently skip.
  exit 0
fi

if [[ $CHECK_EXIT -eq 0 ]]; then
  exit 0
fi

# ── emit deny decision ────────────────────────────────────────────────────────

if [[ "$TOOL_USED" == "pint" ]]; then
  FIX_HINT="Fix with: vendor/bin/pint $FILE_PATH"
else
  FIX_HINT="Address the PHP syntax error reported above."
fi

REASON="php-pint-gate: $TOOL_USED reported issues in $FILE_PATH.

$CHECK_OUTPUT

$FIX_HINT
Bypass once with: CLAUDE_PHP_PINT_GATE_SKIP=1"

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 0
