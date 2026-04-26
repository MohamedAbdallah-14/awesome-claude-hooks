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
      # Escape backslashes first, then double quotes — both are special inside
      # an AppleScript string literal. Order matters; the backslash pass would
      # otherwise re-escape the escapes added by the quote pass.
      as_title="${TITLE//\\/\\\\}"; as_title="${as_title//\"/\\\"}"
      as_body="${BODY//\\/\\\\}";   as_body="${as_body//\"/\\\"}"
      osascript -e "display notification \"${as_body}\" with title \"${as_title}\"" 2>/dev/null || true
    fi
    ;;
  linux)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$TITLE" "$BODY" 2>/dev/null || true
    fi
    ;;
  wsl)
    if command -v powershell.exe >/dev/null 2>&1; then
      # Pass values through the environment so PowerShell sees them as
      # untrusted data, not as code. Avoids any shell or PS injection from
      # arbitrary characters in TITLE/BODY (quotes, backticks, ${}).
      # Also Start-Sleep past the balloon timeout — without it, PowerShell
      # exits and disposes the NotifyIcon before the balloon ever paints.
      CLAUDE_NOTIFY_TITLE_PS="$TITLE" \
      CLAUDE_NOTIFY_BODY_PS="$BODY" \
        powershell.exe -NoProfile -Command '
          Add-Type -AssemblyName System.Windows.Forms | Out-Null
          Add-Type -AssemblyName System.Drawing | Out-Null
          $n = New-Object System.Windows.Forms.NotifyIcon
          $n.Icon = [System.Drawing.SystemIcons]::Information
          $n.BalloonTipTitle = $env:CLAUDE_NOTIFY_TITLE_PS
          $n.BalloonTipText  = $env:CLAUDE_NOTIFY_BODY_PS
          $n.Visible = $true
          $n.ShowBalloonTip(5000)
          Start-Sleep -Seconds 6
          $n.Dispose()
        ' 2>/dev/null || true
    fi
    ;;
  *)
    exit 0
    ;;
esac

exit 0
