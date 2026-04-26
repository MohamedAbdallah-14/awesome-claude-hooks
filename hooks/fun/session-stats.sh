#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   session-stats
# Event:       Stop
# Description: Prints a compact session summary box in the terminal when
#              Claude finishes. Reads from the tmp files written by
#              session-timer.sh. Falls back gracefully if those files don't
#              exist (e.g., session-timer isn't installed).
#
#              Output:
#                ┌─ Session Summary ────────────────────────┐
#                │ Duration: 12 min  │ Tools used: 23        │
#                │ Files edited: 4   │ Bash commands: 8      │
#                └───────────────────────────────────────────┘
#
#              "Files edited" counts unique file paths from usage.csv.
#              "Bash commands" counts Bash rows in usage.csv for this session.
#              Both require log-tool-usage.sh to be installed; otherwise shows 0.
#
# Config (env vars):
#   CLAUDE_SHOW_SESSION_STATS   Set to 0 to disable.  Default: 1
#   CLAUDE_USAGE_LOG            Override usage CSV path.
#   CLAUDE_SESSION_LOG          Override sessions log path.
#
# Install — add to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "hooks": [{ "type": "command", "command": "/path/to/hooks/fun/session-stats.sh" }]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── opt-out ───────────────────────────────────────────────────────────────────

[[ "${CLAUDE_SHOW_SESSION_STATS:-1}" == "1" ]] || exit 0

# ── tty check ────────────────────────────────────────────────────────────────

[[ -t 1 ]] || exit 0

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  exit 0  # silent — stats are a nice-to-have
fi

# ── config ────────────────────────────────────────────────────────────────────

USAGE_LOG="${CLAUDE_USAGE_LOG:-${HOME}/.claude/usage.csv}"

# ── parse stdin to get session_id ────────────────────────────────────────────

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')

# ── read session timer data ───────────────────────────────────────────────────

START_FILE="/tmp/claude-session-${SESSION_ID}.start"
COUNT_FILE="/tmp/claude-session-${SESSION_ID}.count"

NOW=$(date +%s)
DURATION_SECS=0
TOOL_COUNT=0

if [[ -f "$START_FILE" ]]; then
  START=$(cat "$START_FILE" 2>/dev/null || echo "$NOW")
  DURATION_SECS=$(( NOW - START ))
fi

if [[ -f "$COUNT_FILE" ]]; then
  TOOL_COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
fi

# ── format duration ───────────────────────────────────────────────────────────

format_dur() {
  local s=$1
  local h=$(( s / 3600 ))
  local m=$(( (s % 3600) / 60 ))
  if [[ $h -gt 0 ]]; then
    printf '%dh %dm' "$h" "$m"
  elif [[ $m -gt 0 ]]; then
    printf '%d min' "$m"
  else
    printf '%ds' "$s"
  fi
}

DURATION_STR=$(format_dur "$DURATION_SECS")

# ── count bash commands + edited files from usage.csv ────────────────────────

BASH_COUNT=0
EDITED_FILES=0

if [[ -f "$USAGE_LOG" ]]; then
  # Count Bash rows for this session
  BASH_COUNT=$(grep -c "\"${SESSION_ID}\",\"Bash\"" "$USAGE_LOG" 2>/dev/null || echo 0)

  # Count unique file paths (context starting with /) for this session
  EDITED_FILES=$(
    grep "\"${SESSION_ID}\"" "$USAGE_LOG" 2>/dev/null \
    | awk -F'"' '{print $8}' \
    | grep '^/' \
    | sort -u \
    | wc -l \
    | xargs
  )
fi

# ── render box ────────────────────────────────────────────────────────────────

# Box is 45 chars wide inside the borders
LEFT_COL="Duration: ${DURATION_STR}"
RIGHT_COL="Tools used: ${TOOL_COUNT}"
BOT_LEFT="Files edited: ${EDITED_FILES}"
BOT_RIGHT="Bash commands: ${BASH_COUNT}"

# Pad each column to fixed width for alignment
pad() { printf '%-22s' "$1"; }

L1=$(pad "$LEFT_COL")
R1=$(pad "$RIGHT_COL")
L2=$(pad "$BOT_LEFT")
R2=$(pad "$BOT_RIGHT")

# Title bar
TITLE=" Session Summary "
INNER=45
TITLE_PAD=$(( (INNER - ${#TITLE}) / 2 ))
LEFT_DASHES=$(printf '%*s' "$TITLE_PAD" '' | tr ' ' '─')
RIGHT_DASHES=$(printf '%*s' "$(( INNER - TITLE_PAD - ${#TITLE} ))" '' | tr ' ' '─')

printf '\n'
printf '  ┌%s%s%s┐\n' "$LEFT_DASHES" "$TITLE" "$RIGHT_DASHES"
printf '  │ %s │ %s │\n' "$L1" "$R1"
printf '  │ %s │ %s │\n' "$L2" "$R2"
printf '  └%s┘\n' "$(printf '%*s' "$INNER" '' | tr ' ' '─')"
printf '\n'

exit 0
