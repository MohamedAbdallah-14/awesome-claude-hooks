#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   budget-alert
# Event:       PostToolUse
# Description: Tracks a per-session operation count as a proxy for cost.
#              There is no direct API cost data in hook payloads, so operation
#              count is the best available signal.
#
#              At soft threshold (default 50): sends a desktop notification.
#              At hard threshold (default 200): notifies AND emits a JSON
#              context block asking Claude to pause and review.
#
#              Counter file: /tmp/claude-ops-{session_id}.count
#              Notification thresholds: 50, 100, 200
#
# Config (env vars):
#   CLAUDE_BUDGET_SOFT_LIMIT   Ops count for first warning.  Default: 50
#   CLAUDE_BUDGET_HARD_LIMIT   Ops count for hard warning.   Default: 200
#
# Install — add to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": ".*",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/cost/budget-alert.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[budget-alert] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

SOFT_LIMIT="${CLAUDE_BUDGET_SOFT_LIMIT:-50}"
HARD_LIMIT="${CLAUDE_BUDGET_HARD_LIMIT:-200}"

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')

COUNT_FILE="/tmp/claude-ops-${SESSION_ID}.count"

# ── increment counter ─────────────────────────────────────────────────────────

COUNT=0
if [[ -f "$COUNT_FILE" ]]; then
  COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
fi
COUNT=$(( COUNT + 1 ))
printf '%d\n' "$COUNT" > "$COUNT_FILE" 2>/dev/null || true

# ── notification helper ───────────────────────────────────────────────────────

send_notification() {
  local title="$1"
  local message="$2"

  if command -v osascript &>/dev/null; then
    osascript -e "display notification \"${message}\" with title \"${title}\"" 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    notify-send "$title" "$message" 2>/dev/null || true
  else
    # Fallback: print to stderr so it shows in the terminal
    printf '[budget-alert] %s: %s\n' "$title" "$message" >&2
  fi
}

# ── threshold checks ──────────────────────────────────────────────────────────

# Alert exactly at each threshold (not on every subsequent call)
if [[ "$COUNT" -eq "$HARD_LIMIT" ]]; then
  send_notification \
    "Claude Code — High Usage" \
    "⚠️ ${COUNT} operations in this session. Review what's been done before continuing."

  # Emit a context block so Claude sees the warning too
  printf '{"decision":"approve","context":"⚠️ High operation count (%d ops). Consider reviewing progress and confirming whether to continue."}\n' "$COUNT"

elif [[ "$COUNT" -eq 100 ]]; then
  send_notification \
    "Claude Code — Usage Check" \
    "100 operations in this session. Still going."

elif [[ "$COUNT" -eq "$SOFT_LIMIT" ]]; then
  send_notification \
    "Claude Code — Usage Notice" \
    "${COUNT} operations in this session so far."
fi

exit 0
