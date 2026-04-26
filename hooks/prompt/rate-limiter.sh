#!/usr/bin/env bash
# Hook name:   rate-limiter
# Event:       PreToolUse (no matcher — fires on every tool call)
# Description: Tracks tool call frequency per session. If more than 50 calls
#              are made within 60 seconds, injects a warning via additionalContext
#              to prompt Claude to reassess whether it's stuck in a loop.
#              Never blocks — advisory only.
#
# State files: /tmp/claude-rate-<session_id>.txt   — running call count
#              /tmp/claude-rate-<session_id>.ts     — window start timestamp
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/prompt/rate-limiter.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

RATE_LIMIT=50
WINDOW_SECONDS=60

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "default"')
SESSION_ID="${SESSION_ID//[^a-zA-Z0-9_-]/}"  # sanitise for use in filename

COUNT_FILE="/tmp/claude-rate-${SESSION_ID}.txt"
TS_FILE="/tmp/claude-rate-${SESSION_ID}.ts"

NOW=$(date +%s)

# ── window management ─────────────────────────────────────────────────────────

WINDOW_START=0
if [[ -f "$TS_FILE" ]]; then
  WINDOW_START=$(cat "$TS_FILE" 2>/dev/null || echo 0)
fi

ELAPSED=$(( NOW - WINDOW_START ))

if (( ELAPSED >= WINDOW_SECONDS )); then
  # Start a fresh window
  echo "$NOW" > "$TS_FILE"
  echo "1" > "$COUNT_FILE"
  exit 0
fi

# ── increment counter ─────────────────────────────────────────────────────────

COUNT=0
if [[ -f "$COUNT_FILE" ]]; then
  COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
fi

COUNT=$(( COUNT + 1 ))
echo "$COUNT" > "$COUNT_FILE"

# ── threshold check ───────────────────────────────────────────────────────────

if (( COUNT > RATE_LIMIT )); then
  WARN="High tool call rate: ${COUNT} calls in the last ${ELAPSED}s (limit: ${RATE_LIMIT}/${WINDOW_SECONDS}s). If you are in a loop, stop and reassess before continuing."
  jq -n --arg w "$WARN" '{"additionalContext": $w}'
fi

exit 0
