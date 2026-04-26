#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   session-timer
# Event:       PreToolUse (start + count), Stop (log + cleanup)
# Description: Tracks how long each Claude session runs and how many tool calls
#              it makes. Writes a log line to ~/.claude/sessions.log when the
#              session ends.
#
#              Log format (pipe-delimited):
#                ISO_DATE | session_id | duration_seconds | tool_call_count
#
#              Example:
#                2026-04-26 | abc123 | 742 | 87
#
#              Mechanism:
#                PreToolUse — on first call, writes epoch to
#                             /tmp/claude-session-{id}.start
#                             increments /tmp/claude-session-{id}.count
#                Stop       — reads both tmp files, computes elapsed, logs,
#                             then removes tmp files.
#
# Config (env vars):
#   CLAUDE_SESSION_LOG   Override the default log path.
#                        Default: ~/.claude/sessions.log
#
# Install — add BOTH events to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": ".*",
#           "hooks": [{ "type": "command", "command": "/path/to/hooks/cost/session-timer.sh" }]
#         }
#       ],
#       "Stop": [
#         {
#           "hooks": [{ "type": "command", "command": "/path/to/hooks/cost/session-timer.sh" }]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[session-timer] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

SESSION_LOG="${CLAUDE_SESSION_LOG:-${HOME}/.claude/sessions.log}"

# ── ensure log directory exists ───────────────────────────────────────────────

mkdir -p "$(dirname "$SESSION_LOG")" 2>/dev/null || true

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

EVENT=$(printf '%s' "$INPUT"      | jq -r '.hook_event_name // ""')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id      // "unknown"')

START_FILE="/tmp/claude-session-${SESSION_ID}.start"
COUNT_FILE="/tmp/claude-session-${SESSION_ID}.count"

# ── PreToolUse: record start time + increment counter ────────────────────────

if [[ "$EVENT" == "PreToolUse" ]]; then
  # Only write start time on the very first call
  if [[ ! -f "$START_FILE" ]]; then
    date +%s > "$START_FILE" 2>/dev/null || true
  fi

  # Increment call count
  COUNT=0
  if [[ -f "$COUNT_FILE" ]]; then
    COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
  fi
  printf '%d\n' $(( COUNT + 1 )) > "$COUNT_FILE" 2>/dev/null || true

  exit 0
fi

# ── Stop: compute duration, log, clean up ────────────────────────────────────

if [[ "$EVENT" == "Stop" ]]; then
  NOW=$(date +%s)
  ISO_DATE=$(date -u +"%Y-%m-%d")

  # Read start time (default to now if missing — session started before hook)
  START=0
  if [[ -f "$START_FILE" ]]; then
    START=$(cat "$START_FILE" 2>/dev/null || echo "$NOW")
  fi

  DURATION=$(( NOW - START ))

  # Read tool call count
  TOOL_COUNT=0
  if [[ -f "$COUNT_FILE" ]]; then
    TOOL_COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
  fi

  # Append log line
  printf '%s | %s | %d | %d\n' \
    "$ISO_DATE" \
    "$SESSION_ID" \
    "$DURATION" \
    "$TOOL_COUNT" \
    >> "$SESSION_LOG" 2>/dev/null || {
      echo "[session-timer] WARNING: could not write to ${SESSION_LOG}" >&2
    }

  # Clean up tmp files
  rm -f "$START_FILE" "$COUNT_FILE" 2>/dev/null || true

  exit 0
fi

# Unknown event — do nothing
exit 0
