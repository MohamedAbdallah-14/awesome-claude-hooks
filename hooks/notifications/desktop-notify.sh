#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   desktop-notify
# Event:       Stop
# Description: Cross-platform desktop notification when Claude Code finishes a task.
#              macOS: osascript banner. Linux: notify-send. WSL: PowerShell toast.
#              Exits 0 silently on unsupported platforms.
#
# Config (env vars):
#   CLAUDE_NOTIFY_TITLE   Override notification title (default: "Claude Code").
#   CLAUDE_NOTIFY_BODY    Override notification body (default: "Task complete").
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
#               "command": "/path/to/hooks/notifications/desktop-notify.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# shellcheck source=../_lib/os-detect.sh
source "$(dirname "$0")/../_lib/os-detect.sh"

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)

TITLE="${CLAUDE_NOTIFY_TITLE:-Claude Code}"
BODY="${CLAUDE_NOTIFY_BODY:-Task complete}"
if [[ -n "$SESSION_ID" && "$SESSION_ID" != "null" ]]; then
  BODY="${BODY} · …${SESSION_ID: -8}"
fi

case "$CLAUDE_OS" in
  macos)
    if command -v osascript >/dev/null 2>&1; then
      osascript -e "display notification \"${BODY}\" with title \"${TITLE}\"" 2>/dev/null || true
    fi
    ;;
  linux)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$TITLE" "$BODY" 2>/dev/null || true
    fi
    ;;
  wsl)
    if command -v powershell.exe >/dev/null 2>&1; then
      # Escape double quotes in the body for PowerShell.
      ps_body="${BODY//\"/\`\"}"
      ps_title="${TITLE//\"/\`\"}"
      powershell.exe -NoProfile -Command \
        "[reflection.assembly]::loadwithpartialname('System.Windows.Forms') | Out-Null; \
         [reflection.assembly]::loadwithpartialname('System.Drawing') | Out-Null; \
         \$n = New-Object System.Windows.Forms.NotifyIcon; \
         \$n.Icon = [System.Drawing.SystemIcons]::Information; \
         \$n.BalloonTipTitle = \"${ps_title}\"; \
         \$n.BalloonTipText = \"${ps_body}\"; \
         \$n.Visible = \$true; \
         \$n.ShowBalloonTip(3000)" 2>/dev/null || true
    fi
    ;;
  *)
    exit 0
    ;;
esac

exit 0
