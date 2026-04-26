#!/usr/bin/env bash
# Hook name:   slack-notify
# Event:       Stop
# Description: Posts a Slack message via an Incoming Webhook when Claude Code
#              finishes a task. Message includes session ID, timestamp, and
#              working directory.
#
# Config (env vars):
#   CLAUDE_SLACK_WEBHOOK    REQUIRED. Incoming webhook URL from Slack app config.
#   CLAUDE_SLACK_CHANNEL    Optional. Override channel, e.g. "#dev-alerts".
#   CLAUDE_SLACK_USERNAME   Optional. Display name (default: "Claude Code").
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
#               "command": "/path/to/hooks/notifications/slack-notify.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v curl &>/dev/null; then
  echo "[slack-notify] WARNING: curl not found — cannot post to Slack" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[slack-notify] WARNING: jq not found — install it (brew install jq / apt install jq)" >&2
  exit 0
fi

# ── config validation ─────────────────────────────────────────────────────────

WEBHOOK_URL="${CLAUDE_SLACK_WEBHOOK:-}"
if [[ -z "$WEBHOOK_URL" ]]; then
  echo "[slack-notify] WARNING: CLAUDE_SLACK_WEBHOOK is not set — skipping" >&2
  exit 0
fi

USERNAME="${CLAUDE_SLACK_USERNAME:-Claude Code}"
CHANNEL="${CLAUDE_SLACK_CHANNEL:-}"

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
WORKDIR="${PWD:-unknown}"

# ── build payload ─────────────────────────────────────────────────────────────

# Use jq to safely build JSON so special chars in WORKDIR/USERNAME don't break it
PAYLOAD=$(jq -n \
  --arg text ":white_check_mark: *Claude Code task complete*" \
  --arg session "$SESSION_ID" \
  --arg ts "$TIMESTAMP" \
  --arg dir "$WORKDIR" \
  --arg username "$USERNAME" \
  --arg channel "$CHANNEL" \
  '{
    username: $username,
    text: $text,
    attachments: [
      {
        color: "good",
        fields: [
          { title: "Session", value: $session, short: true },
          { title: "Finished at", value: $ts, short: true },
          { title: "Directory", value: $dir, short: false }
        ]
      }
    ]
  }
  | if $channel != "" then . + {channel: $channel} else . end'
)

# ── post to Slack ─────────────────────────────────────────────────────────────

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

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "[slack-notify] WARNING: Slack responded with HTTP ${HTTP_STATUS}" >&2
fi

exit 0
