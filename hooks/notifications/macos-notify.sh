#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   macos-notify
# Event:       Stop
# Description: Shows a macOS notification banner when Claude Code finishes a task.
#              Falls back gracefully on non-macOS systems (exits 0 silently).
#
# Config (env vars):
#   CLAUDE_NOTIFY_SOUND   Optional. macOS sound name, e.g. "Glass", "Ping", "Basso".
#                         Omit or leave empty to suppress sound.
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
#               "command": "/path/to/hooks/notifications/macos-notify.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

# Only meaningful on macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if ! command -v osascript &>/dev/null; then
  echo "[macos-notify] WARNING: osascript not found — skipping notification" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[macos-notify] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)

# Build a short session snippet for the body (last 8 chars is enough to identify)
if [[ -n "$SESSION_ID" && "$SESSION_ID" != "null" ]]; then
  SHORT_ID="${SESSION_ID: -8}"
  BODY="Task complete · session …${SHORT_ID}"
else
  BODY="Task complete"
fi

TITLE="Claude Code"
SOUND="${CLAUDE_NOTIFY_SOUND:-}"

# ── fire notification ─────────────────────────────────────────────────────────

if [[ -n "$SOUND" ]]; then
  osascript \
    -e "display notification \"${BODY}\" with title \"${TITLE}\" sound name \"${SOUND}\"" \
    2>/dev/null || true
else
  osascript \
    -e "display notification \"${BODY}\" with title \"${TITLE}\"" \
    2>/dev/null || true
fi

exit 0
