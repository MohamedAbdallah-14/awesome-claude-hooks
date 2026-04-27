#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   ai-migration-safety
# Event:       PreToolUse (matcher: "Bash")
# Mode:        BLOCKING (exit 2 on IRREVERSIBLE migrations)
# Description: Intercepts bash commands that look like database migrations.
#              Asks Haiku whether the migration is REVERSIBLE, IRREVERSIBLE, or
#              UNKNOWN. Blocks with exit 2 only if IRREVERSIBLE. Passes through
#              if REVERSIBLE, UNKNOWN, or if the API key is absent.
#
# Config (env vars):
#   ANTHROPIC_API_KEY   If absent, hook allows all migrations through.
#
# Install — add to .claude/settings.json:
#   { "hooks": { "PreToolUse": [{ "matcher": "Bash",
#     "hooks": [{ "type": "command",
#       "command": "/path/to/hooks/ai/ai-migration-safety.sh" }] }] } }

set -euo pipefail

INPUT=$(cat)

# ── dependency checks ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null; then exit 0; fi

# ── parse command ──────────────────────────────────────────────────────────────
COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT")
if [[ -z "$COMMAND" ]]; then exit 0; fi

# ── detect migration keywords ──────────────────────────────────────────────────
if ! echo "$COMMAND" | grep -qiE '(^|[[:space:]])(migrate|db:migrate|flyway[[:space:]]+migrate|liquibase[[:space:]]+update|alembic[[:space:]]+upgrade)([[:space:]]|$)'; then
  exit 0
fi

# ── no API key → allow through ─────────────────────────────────────────────────
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$ANTHROPIC_API_KEY" ]]; then exit 0; fi

# ── call Haiku ─────────────────────────────────────────────────────────────────
PROMPT=$(jq -n --arg cmd "$COMMAND" \
  '"Is this database migration command reversible? Reply with exactly one of: REVERSIBLE, IRREVERSIBLE, or UNKNOWN on the first line. Then one sentence explaining why.\n\nCommand: " + $cmd')

RESPONSE=$(curl -sf https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":150,\"messages\":[{\"role\":\"user\",\"content\":$PROMPT}]}" \
  || true)

# ── parse verdict ──────────────────────────────────────────────────────────────
if [[ -z "$RESPONSE" ]]; then exit 0; fi

TEXT=$(jq -r '.content[0].text // empty' <<< "$RESPONSE")
if [[ -z "$TEXT" ]]; then exit 0; fi

VERDICT=$(echo "$TEXT" | head -1 | tr '[:lower:]' '[:upper:]' | tr -d ' \r')
REASON=$(echo "$TEXT" | tail -n +2 | head -1 | sed 's/^[[:space:]]*//')

# ── act on verdict ─────────────────────────────────────────────────────────────
if [[ "$VERDICT" == "IRREVERSIBLE" ]]; then
  BLOCK_MSG="Migration blocked: Haiku assessed this as IRREVERSIBLE."
  if [[ -n "$REASON" ]]; then
    BLOCK_MSG="$BLOCK_MSG $REASON"
  fi
  jq -n --arg r "$BLOCK_MSG" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
fi

# REVERSIBLE or UNKNOWN: allow through
exit 0
