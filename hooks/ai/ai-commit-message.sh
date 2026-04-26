#!/usr/bin/env bash
# Hook name:   ai-commit-message
# Event:       Stop
# Description: At session end, checks if the last commit message is generic
#              (≤15 chars or matches common lazy patterns). If so, calls Haiku
#              with the diff stat to suggest a conventional commit message.
#              Purely advisory — outputs additionalContext, never blocks.
#
# Config (env vars):
#   ANTHROPIC_API_KEY   Required. If absent, hook skips silently.
#
# Install — add to .claude/settings.json:
#   { "hooks": { "Stop": [{ "hooks": [{ "type": "command",
#     "command": "/path/to/hooks/ai/ai-commit-message.sh" }] }] } }

set -euo pipefail

INPUT=$(cat)

# ── dependency checks ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null; then exit 0; fi

ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$ANTHROPIC_API_KEY" ]]; then exit 0; fi

# ── check git repo ─────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then exit 0; fi
if ! git rev-parse --git-dir &>/dev/null 2>&1; then exit 0; fi

# ── grab last commit message ───────────────────────────────────────────────────
LAST_MSG=$(git log -1 --format="%s" 2>/dev/null || true)
if [[ -z "$LAST_MSG" ]]; then exit 0; fi

# ── decide if the message is worth improving ───────────────────────────────────
MSG_LEN=${#LAST_MSG}
NEEDS_IMPROVEMENT=0

if (( MSG_LEN <= 15 )); then
  NEEDS_IMPROVEMENT=1
fi

# Match common lazy patterns (case-insensitive)
if echo "$LAST_MSG" | grep -qiE '^(fix|fixes|fixed|update|updates|updated|changes|change|wip|misc|stuff|done|work|commit|save|temp|test)\.?$'; then
  NEEDS_IMPROVEMENT=1
fi

if [[ "$NEEDS_IMPROVEMENT" -eq 0 ]]; then exit 0; fi

# ── gather diff stat ───────────────────────────────────────────────────────────
DIFF_STAT=$(git diff HEAD~1 --stat 2>/dev/null | tail -20 || true)
if [[ -z "$DIFF_STAT" ]]; then exit 0; fi

# ── call Haiku ─────────────────────────────────────────────────────────────────
PROMPT=$(jq -Rs --arg msg "$LAST_MSG" \
  '"The last git commit has a poor message: \"" + $msg + "\"\n\nDiff stat:\n" + . + "\n\nSuggest one improved commit message following Conventional Commits (e.g. feat(scope): description). Reply with ONLY the commit message, nothing else."' \
  <<< "$DIFF_STAT")

RESPONSE=$(curl -sf https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":100,\"messages\":[{\"role\":\"user\",\"content\":$PROMPT}]}" \
  || true)

if [[ -z "$RESPONSE" ]]; then exit 0; fi

SUGGESTION=$(jq -r '.content[0].text // empty' <<< "$RESPONSE" | head -1 | tr -d '\n')
if [[ -z "$SUGGESTION" ]]; then exit 0; fi

# ── output advisory context ────────────────────────────────────────────────────
jq -n --arg msg "Suggested commit message: $SUGGESTION" \
  '{"additionalContext": $msg}'
