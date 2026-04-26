#!/usr/bin/env bash
# Hook name:   pushover-notify
# Event:       Stop
# Description: Sends a push notification to iOS or Android via the Pushover API
#              when Claude Code finishes a task.
#
# Config (env vars):
#   CLAUDE_PUSHOVER_TOKEN      REQUIRED. Application API token from pushover.net.
#   CLAUDE_PUSHOVER_USER       REQUIRED. User/group key from pushover.net dashboard.
#   CLAUDE_PUSHOVER_PRIORITY   Optional. -2 (silent) to 2 (emergency). Default: 0.
#                              Note: priority 2 (emergency) requires retry + expire
#                              params; this hook caps at priority 1 for simplicity.
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
#               "command": "/path/to/hooks/notifications/pushover-notify.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v curl &>/dev/null; then
  echo "[pushover-notify] WARNING: curl not found — cannot send push notification" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[pushover-notify] WARNING: jq not found — install it (brew install jq / apt install jq)" >&2
  exit 0
fi

# ── config validation ─────────────────────────────────────────────────────────

PUSHOVER_TOKEN="${CLAUDE_PUSHOVER_TOKEN:-}"
PUSHOVER_USER="${CLAUDE_PUSHOVER_USER:-}"

if [[ -z "$PUSHOVER_TOKEN" ]]; then
  echo "[pushover-notify] WARNING: CLAUDE_PUSHOVER_TOKEN is not set — skipping" >&2
  exit 0
fi

if [[ -z "$PUSHOVER_USER" ]]; then
  echo "[pushover-notify] WARNING: CLAUDE_PUSHOVER_USER is not set — skipping" >&2
  exit 0
fi

# Clamp priority to [-1, 1] — priority 2 (emergency) needs retry/expire params
# that we don't support here; use a dedicated integration for that.
RAW_PRIORITY="${CLAUDE_PUSHOVER_PRIORITY:-0}"
PRIORITY=$(( RAW_PRIORITY > 1 ? 1 : (RAW_PRIORITY < -2 ? -2 : RAW_PRIORITY) ))

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
WORKDIR="${PWD:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

MESSAGE="Task complete
Session: ${SESSION_ID}
Dir: ${WORKDIR}
At: ${TIMESTAMP}"

TITLE="Claude Code"

# ── send push notification ────────────────────────────────────────────────────

RESPONSE=$(curl \
  --silent \
  --max-time 10 \
  --retry 2 \
  --retry-delay 2 \
  --form-string "token=${PUSHOVER_TOKEN}" \
  --form-string "user=${PUSHOVER_USER}" \
  --form-string "title=${TITLE}" \
  --form-string "message=${MESSAGE}" \
  --form-string "priority=${PRIORITY}" \
  "https://api.pushover.net/1/messages.json" \
) || true

# Pushover returns {"status":1} on success
STATUS=$(printf '%s' "$RESPONSE" | jq -r '.status // 0' 2>/dev/null || echo "0")
if [[ "$STATUS" != "1" ]]; then
  ERRORS=$(printf '%s' "$RESPONSE" | jq -r '.errors // [] | join(", ")' 2>/dev/null || true)
  echo "[pushover-notify] WARNING: Pushover API error: ${ERRORS:-unknown}" >&2
fi

exit 0
