#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   aws-prod-guard
# Event:       PreToolUse (matcher: "Bash")
# Description: Blocks destructive AWS CLI commands targeting production profiles.
#
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/devops/aws-prod-guard.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT")

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only care about aws CLI commands
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]])aws[[:space:]]'; then
  exit 0
fi

block() {
  local reason="$1"
  printf '{"decision":"block","reason":"%s"}' "$reason"
  exit 2
}

if [[ "${CLAUDE_ALLOW_AWS_PROD:-}" == "1" ]]; then
  exit 0
fi

# Readonly subcommands — always allow regardless of profile
READONLY_PATTERN='(describe|list|get|ls|head|lookup|scan|query|search|show|check|test|validate|preview|estimate|forecast|explain)'
if echo "$COMMAND" | grep -qE "[[:space:]]${READONLY_PATTERN}[-_[:alnum:]]*([[:space:]]|$)"; then
  exit 0
fi

# Detect production profile: --profile prod*, AWS_PROFILE=prod*, AWS_DEFAULT_PROFILE=prod*
TARGETS_PROD=0

if echo "$COMMAND" | grep -qE '\-\-profile[[:space:]]+prod[[:alnum:]-_]*'; then
  TARGETS_PROD=1
fi

if [[ "${AWS_PROFILE:-}" =~ ^prod ]]; then
  TARGETS_PROD=1
fi

if [[ "${AWS_DEFAULT_PROFILE:-}" =~ ^prod ]]; then
  TARGETS_PROD=1
fi

if [[ "$TARGETS_PROD" -eq 0 ]]; then
  exit 0
fi

# Destructive operation patterns
DESTRUCTIVE_PATTERN='(delete|terminate|destroy|remove|deregister|detach|disassociate|disable|revoke|deprovision|drain|stop|cancel|purge|wipe|retire|reset)'
if echo "$COMMAND" | grep -qiE "[[:space:]]${DESTRUCTIVE_PATTERN}[-_[:alnum:]]*([[:space:]]|$)"; then
  MATCHED=$(echo "$COMMAND" | grep -oiE "[[:space:]]${DESTRUCTIVE_PATTERN}[-_[:alnum:]]*" | head -1 | tr -d ' ')
  block "AWS command targets production profile with destructive operation '${MATCHED}'. Set CLAUDE_ALLOW_AWS_PROD=1 to allow."
fi

# Catch-all for prod-profile commands that aren't clearly readonly
block "AWS command targets production profile. Set CLAUDE_ALLOW_AWS_PROD=1 to allow."
