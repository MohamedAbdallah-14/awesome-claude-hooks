#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   swiftlint-gate
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .swift file, runs `swiftlint lint --quiet
#              --use-stdin` against the file contents. Blocks the change with
#              a deny decision when SwiftLint reports any issue. Silently
#              skips when swiftlint isn't on PATH.
#
#              Matches: .swift
#
# Config (env vars):
#   CLAUDE_SWIFTLINT_GATE_SKIP=1   Skip this gate entirely (silent pass). Default: gate enforced.
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
#               "command": "/path/to/hooks/quality/swiftlint-gate.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── bypass switch ─────────────────────────────────────────────────────────────

if [[ "${CLAUDE_SWIFTLINT_GATE_SKIP:-0}" == "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[swiftlint-gate] WARNING: jq not found — install it with: brew install jq" >&2
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
  *.swift) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── swiftlint availability ────────────────────────────────────────────────────

if ! command -v swiftlint &>/dev/null; then
  exit 0
fi

# ── run swiftlint via stdin ───────────────────────────────────────────────────

LINT_OUTPUT=""
LINT_EXIT=0
LINT_OUTPUT=$(cat "$FILE_PATH" | swiftlint lint --quiet --use-stdin 2>&1) || LINT_EXIT=$?

# swiftlint exits 0 even with warnings unless --strict is used; treat any
# output line containing "warning:" or "error:" as a failure.
HAS_ISSUES=0
if [[ $LINT_EXIT -ne 0 ]]; then
  HAS_ISSUES=1
elif printf '%s\n' "$LINT_OUTPUT" | grep -Eq '(warning|error):'; then
  HAS_ISSUES=1
fi

if [[ $HAS_ISSUES -eq 0 ]]; then
  exit 0
fi

# ── emit deny decision ────────────────────────────────────────────────────────

REASON="swiftlint-gate: swiftlint reported issues in $FILE_PATH.

$LINT_OUTPUT

Fix with: swiftlint --fix --path $FILE_PATH
Bypass once with: CLAUDE_SWIFTLINT_GATE_SKIP=1"

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 0
