#!/usr/bin/env bash
# Hook name:   telegram-notify
# Event:       Stop
# Description: Sends a Telegram message via the Bot API when Claude Code
#              finishes a task.
#
# Config (env vars):
#   CLAUDE_TELEGRAM_BOT_TOKEN   REQUIRED. Bot token from @BotFather.
#   CLAUDE_TELEGRAM_CHAT_ID     REQUIRED. Target chat/channel ID. Get yours by
#                               messaging your bot and calling:
#                               https://api.telegram.org/bot<TOKEN>/getUpdates
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
#               "command": "/path/to/hooks/notifications/telegram-notify.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v curl &>/dev/null; then
  echo "[telegram-notify] WARNING: curl not found — cannot send Telegram message" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[telegram-notify] WARNING: jq not found — install it (brew install jq / apt install jq)" >&2
  exit 0
fi

# ── config validation ─────────────────────────────────────────────────────────

BOT_TOKEN="${CLAUDE_TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${CLAUDE_TELEGRAM_CHAT_ID:-}"

if [[ -z "$BOT_TOKEN" ]]; then
  echo "[telegram-notify] WARNING: CLAUDE_TELEGRAM_BOT_TOKEN is not set — skipping" >&2
  exit 0
fi

if [[ -z "$CHAT_ID" ]]; then
  echo "[telegram-notify] WARNING: CLAUDE_TELEGRAM_CHAT_ID is not set — skipping" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
WORKDIR="${PWD:-unknown}"

# Build message — use jq to safely escape the text for JSON
MESSAGE=$(jq -rn \
  --arg session "$SESSION_ID" \
  --arg dir "$WORKDIR" \
  '"✅ Claude Code task complete\nSession: \($session)\nDir: \($dir)"'
)

# ── send message ──────────────────────────────────────────────────────────────

API_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

PAYLOAD=$(jq -n \
  --arg chat_id "$CHAT_ID" \
  --arg text "$MESSAGE" \
  '{chat_id: $chat_id, text: $text}'
)

RESPONSE=$(curl \
  --silent \
  --max-time 10 \
  --retry 2 \
  --retry-delay 2 \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$API_URL" \
) || true

OK=$(printf '%s' "$RESPONSE" | jq -r '.ok // false' 2>/dev/null || echo "false")
if [[ "$OK" != "true" ]]; then
  DESCRIPTION=$(printf '%s' "$RESPONSE" | jq -r '.description // "unknown error"' 2>/dev/null || true)
  echo "[telegram-notify] WARNING: Telegram API error: ${DESCRIPTION}" >&2
fi

exit 0
