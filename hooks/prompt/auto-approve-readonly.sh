#!/usr/bin/env bash
# Hook name:   auto-approve-readonly
# Event:       PermissionRequest (no matcher needed — fires for every tool request)
# Description: Auto-approves read-only tool requests so Claude can explore freely
#              without interrupting the user. For any non-read-only tool, outputs
#              nothing and lets Claude Code apply its normal permission logic.
#
# Read-only tools approved: Read, Glob, Grep, LS, WebSearch, WebFetch, TodoRead
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PermissionRequest": [
#         {
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/prompt/auto-approve-readonly.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-approve-readonly] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

if [[ -z "$TOOL_NAME" ]]; then
  exit 0
fi

# ── decision ──────────────────────────────────────────────────────────────────

case "$TOOL_NAME" in
  Read|Glob|Grep|LS|WebSearch|WebFetch|TodoRead)
    jq -n '{"hookSpecificOutput":{"permissionDecision":"allow","updatedInput":{}}}'
    ;;
  *)
    # Emit nothing — let Claude Code decide via its normal permission flow.
    exit 0
    ;;
esac
