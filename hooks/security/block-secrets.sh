#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   block-secrets
# Event:       PreToolUse (matcher: "Write|Edit|MultiEdit")
# Description: Scans file content about to be written for hardcoded secrets.
#              Matches common API key, token, and credential patterns.
#              Blocks the write if any pattern is found.
#
# Patterns detected:
#   - OpenAI API key        sk-[a-zA-Z0-9]{48}
#   - AWS Access Key ID     AKIA[0-9A-Z]{16}
#   - GitHub personal token ghp_[a-zA-Z0-9]{36}
#   - Slack bot token       xoxb-[0-9-a-zA-Z]{51}
#   - password assignment   password = "..."
#   - secret assignment     secret = "..."
#   - api_key assignment    api_key = "..."
#
# Config (env vars):
#   CLAUDE_ALLOW_SECRETS=1   Disable blocking (useful for test fixtures).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Write|Edit|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/security/block-secrets.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[block-secrets] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_ALLOW_SECRETS:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

# Extract the content being written depending on the tool
case "$TOOL_NAME" in
  Write)
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""')
    ;;
  Edit|MultiEdit)
    # For Edit: new_string. For MultiEdit: collect all new_string values.
    CONTENT=$(printf '%s' "$INPUT" | jq -r '
      .tool_input.new_string //
      (.tool_input.edits // [] | map(.new_string // "") | join("\n")) //
      ""
    ')
    ;;
  *)
    exit 0
    ;;
esac

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# ── pattern matching ──────────────────────────────────────────────────────────

# Each entry: "LABEL|REGEX"
# Using grep -E; patterns are POSIX ERE.
declare -a PATTERNS=(
  "OpenAI API key|sk-[a-zA-Z0-9]{48}"
  "AWS Access Key ID|AKIA[0-9A-Z]{16}"
  "GitHub personal access token|ghp_[a-zA-Z0-9]{36}"
  "Slack bot token|xoxb-[0-9A-Za-z-]{51}"
  "password assignment|[Pp]assword[[:space:]]*=[[:space:]]*[\"'][^\"']{8,}[\"']"
  "secret assignment|[Ss]ecret[[:space:]]*=[[:space:]]*[\"'][^\"']{8,}[\"']"
  "api_key assignment|[Aa]pi_[Kk]ey[[:space:]]*=[[:space:]]*[\"'][^\"']{8,}[\"']"
)

MATCHED_LABEL=""

for entry in "${PATTERNS[@]}"; do
  label="${entry%%|*}"
  regex="${entry##*|}"
  if printf '%s' "$CONTENT" | grep -qE "$regex" 2>/dev/null; then
    MATCHED_LABEL="$label"
    break
  fi
done

# ── decision ──────────────────────────────────────────────────────────────────

if [[ -n "$MATCHED_LABEL" ]]; then
  jq -n \
    --arg reason "Blocked: potential hardcoded secret detected (matched pattern: ${MATCHED_LABEL}). Move credentials to environment variables or a secrets manager. Set CLAUDE_ALLOW_SECRETS=1 to override for test fixtures." \
    '{"decision":"block","reason":$reason}'
  exit 2
fi

exit 0
