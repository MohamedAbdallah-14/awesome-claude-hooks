#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   break-reminder
# Event:       Stop
# Description: Watches your cumulative Claude session time for the day. When
#              you've been working with Claude for over 90 minutes total, it
#              sends a desktop notification to take a break.
#
#              Rate-limited to once per 30 minutes so it doesn't nag.
#
#              Reads ~/.claude/sessions.log (written by session-timer.sh) to
#              sum today's session durations.
#
#              Notification methods tried in order:
#                1. osascript (macOS)
#                2. notify-send (Linux/GNOME)
#                3. stderr fallback
#
# Config (env vars):
#   CLAUDE_BREAK_REMINDER_INTERVAL   Minutes of total use before first alert.
#                                    Default: 90
#   CLAUDE_SESSION_LOG               Override sessions log path.
#                                    Default: ~/.claude/sessions.log
#
# Install — add to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "hooks": [{ "type": "command", "command": "/path/to/hooks/fun/break-reminder.sh" }]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────

INTERVAL_MINS="${CLAUDE_BREAK_REMINDER_INTERVAL:-90}"
SESSION_LOG="${CLAUDE_SESSION_LOG:-${HOME}/.claude/sessions.log}"
REMINDED_FILE="/tmp/claude-break-reminded.time"
COOLDOWN_SECS=1800  # 30 minutes between reminders

# ── rate limit: skip if reminded recently ────────────────────────────────────

NOW=$(date +%s)
if [[ -f "$REMINDED_FILE" ]]; then
  LAST=$(cat "$REMINDED_FILE" 2>/dev/null || echo 0)
  SINCE=$(( NOW - LAST ))
  if [[ "$SINCE" -lt "$COOLDOWN_SECS" ]]; then
    exit 0
  fi
fi

# ── sum today's session durations ────────────────────────────────────────────

TODAY=$(date -u +"%Y-%m-%d")
TOTAL_SECS=0

if [[ -f "$SESSION_LOG" ]]; then
  while IFS='|' read -r date _sid duration _count; do
    date=$(printf '%s' "$date" | xargs)
    [[ "$date" != "$TODAY" ]] && continue
    dur=$(printf '%s' "$duration" | xargs)
    # Validate it's a number
    [[ "$dur" =~ ^[0-9]+$ ]] || continue
    TOTAL_SECS=$(( TOTAL_SECS + dur ))
  done < "$SESSION_LOG"
fi

TOTAL_MINS=$(( TOTAL_SECS / 60 ))
THRESHOLD_SECS=$(( INTERVAL_MINS * 60 ))

# ── check threshold ───────────────────────────────────────────────────────────

if [[ "$TOTAL_SECS" -lt "$THRESHOLD_SECS" ]]; then
  exit 0
fi

# ── send notification ─────────────────────────────────────────────────────────

MSG="You've been working with Claude for ${TOTAL_MINS} min today. Take a 5-min break."
TITLE="Claude Code — Break Reminder"

if command -v osascript &>/dev/null; then
  osascript -e "display notification \"${MSG}\" with title \"${TITLE}\"" 2>/dev/null || true
elif command -v notify-send &>/dev/null; then
  notify-send "$TITLE" "$MSG" 2>/dev/null || true
else
  printf '\n[break-reminder] %s\n' "$MSG" >&2
fi

# ── record reminder time ──────────────────────────────────────────────────────

printf '%d\n' "$NOW" > "$REMINDED_FILE" 2>/dev/null || true

exit 0
