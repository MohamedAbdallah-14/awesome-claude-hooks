#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   ktlint-gate
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .kt or .kts file, runs `ktlint <file>`.
#              Blocks the change with a deny decision on any lint error so
#              Claude can re-run with --format applied or fix the offences
#              manually. Silently skips when ktlint isn't on PATH.
#
#              Matches: .kt  .kts
#
# Config (env vars):
#   CLAUDE_KTLINT_GATE_SKIP=1   Skip this gate entirely (silent pass). Default: gate enforced.
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
#               "command": "/path/to/hooks/quality/ktlint-gate.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── bypass switch ─────────────────────────────────────────────────────────────

if [[ "${CLAUDE_KTLINT_GATE_SKIP:-0}" == "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[ktlint-gate] WARNING: jq not found — install it with: brew install jq" >&2
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
  *.kt|*.kts) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── ktlint availability ───────────────────────────────────────────────────────

if ! command -v ktlint &>/dev/null; then
  exit 0
fi

# ── run ktlint ────────────────────────────────────────────────────────────────

LINT_OUTPUT=""
LINT_EXIT=0
LINT_OUTPUT=$(ktlint "$FILE_PATH" 2>&1) || LINT_EXIT=$?

if [[ $LINT_EXIT -eq 0 ]]; then
  exit 0
fi

# ── emit deny decision ────────────────────────────────────────────────────────

REASON="ktlint-gate: ktlint reported issues in $FILE_PATH.

$LINT_OUTPUT

Fix with: ktlint --format $FILE_PATH
Bypass once with: CLAUDE_KTLINT_GATE_SKIP=1"

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 0
