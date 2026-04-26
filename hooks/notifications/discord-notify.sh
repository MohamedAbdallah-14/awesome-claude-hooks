#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   discord-notify
# Event:       Stop
# Description: Posts a Discord embed message via a webhook when Claude Code
#              finishes a task. Message includes session ID, timestamp, and
#              working directory.
#
# Config (env vars):
#   CLAUDE_DISCORD_WEBHOOK   REQUIRED. Discord webhook URL (Settings → Integrations
#                            → Webhooks in any Discord channel).
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
#               "command": "/path/to/hooks/notifications/discord-notify.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v curl &>/dev/null; then
  echo "[discord-notify] WARNING: curl not found — cannot post to Discord" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[discord-notify] WARNING: jq not found — install it (brew install jq / apt install jq)" >&2
  exit 0
fi

# ── config validation ─────────────────────────────────────────────────────────

WEBHOOK_URL="${CLAUDE_DISCORD_WEBHOOK:-}"
if [[ -z "$WEBHOOK_URL" ]]; then
  echo "[discord-notify] WARNING: CLAUDE_DISCORD_WEBHOOK is not set — skipping" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
WORKDIR="${PWD:-unknown}"

# Discord color: green = 3066993
PAYLOAD=$(jq -n \
  --arg session "$SESSION_ID" \
  --arg ts "$TIMESTAMP" \
  --arg dir "$WORKDIR" \
  '{
    username: "Claude Code",
    embeds: [
      {
        title: "Task complete",
        color: 3066993,
        fields: [
          { name: "Session", value: $session, inline: true },
          { name: "Finished at", value: $ts, inline: true },
          { name: "Directory", value: $dir, inline: false }
        ],
        footer: { text: "Claude Code hook · discord-notify" }
      }
    ]
  }'
)

# ── post to Discord ───────────────────────────────────────────────────────────

HTTP_STATUS=$(curl \
  --silent \
  --output /dev/null \
  --write-out "%{http_code}" \
  --max-time 10 \
  --retry 2 \
  --retry-delay 2 \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$WEBHOOK_URL" \
) || true

# Discord returns 204 No Content on success
if [[ "$HTTP_STATUS" != "204" && "$HTTP_STATUS" != "200" ]]; then
  echo "[discord-notify] WARNING: Discord responded with HTTP ${HTTP_STATUS}" >&2
fi

exit 0
