#!/usr/bin/env bash
# Hook name:   linux-notify
# Event:       Stop
# Description: Sends a Linux desktop notification via notify-send when Claude
#              Code finishes a task. Falls back gracefully on macOS / systems
#              without notify-send.
#
# Config (env vars):
#   CLAUDE_NOTIFY_URGENCY   low | normal | critical  (default: normal)
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "matcher": "",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/notifications/linux-notify.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Linux" ]]; then
  exit 0
fi

if ! command -v notify-send &>/dev/null; then
  echo "[linux-notify] WARNING: notify-send not found — install libnotify-bin" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[linux-notify] WARNING: jq not found — install it with your package manager" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)

if [[ -n "$SESSION_ID" && "$SESSION_ID" != "null" ]]; then
  SHORT_ID="${SESSION_ID: -8}"
  BODY="Task complete · session …${SHORT_ID}"
else
  BODY="Task complete"
fi

URGENCY="${CLAUDE_NOTIFY_URGENCY:-normal}"

# Validate urgency value to avoid notify-send errors
case "$URGENCY" in
  low|normal|critical) ;;
  *)
    echo "[linux-notify] WARNING: invalid CLAUDE_NOTIFY_URGENCY='${URGENCY}', using 'normal'" >&2
    URGENCY="normal"
    ;;
esac

# ── fire notification ─────────────────────────────────────────────────────────

notify-send \
  --urgency="$URGENCY" \
  --icon=dialog-information \
  "Claude Code" \
  "$BODY" \
  2>/dev/null || true

exit 0
