#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   rubocop-gate
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .rb file, runs
#              `rubocop --force-exclusion --no-color --format quiet <file>`.
#              Blocks the change with a deny decision on any offence so
#              Claude can re-run with rubocop -A applied. Silently skips
#              when rubocop isn't on PATH.
#
#              Matches: .rb
#
# Config (env vars):
#   CLAUDE_RUBOCOP_GATE_SKIP=1   Skip this gate entirely (silent pass). Default: gate enforced.
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
#               "command": "/path/to/hooks/quality/rubocop-gate.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── bypass switch ─────────────────────────────────────────────────────────────

if [[ "${CLAUDE_RUBOCOP_GATE_SKIP:-0}" == "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[rubocop-gate] WARNING: jq not found — install it with: brew install jq" >&2
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
  *.rb) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── rubocop availability ──────────────────────────────────────────────────────

if ! command -v rubocop &>/dev/null; then
  exit 0
fi

# ── run rubocop ───────────────────────────────────────────────────────────────

LINT_OUTPUT=""
LINT_EXIT=0
LINT_OUTPUT=$(rubocop --force-exclusion --no-color --format quiet "$FILE_PATH" 2>&1) || LINT_EXIT=$?

if [[ $LINT_EXIT -eq 0 ]]; then
  exit 0
fi

# ── emit deny decision ────────────────────────────────────────────────────────

REASON="rubocop-gate: rubocop reported offences in $FILE_PATH.

$LINT_OUTPUT

Fix with: rubocop -A $FILE_PATH
Bypass once with: CLAUDE_RUBOCOP_GATE_SKIP=1"

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 0
