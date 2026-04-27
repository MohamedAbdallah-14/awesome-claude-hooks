#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   docker-prod-guard
# Event:       PreToolUse (matcher: "Bash")
# Description: Blocks docker rm/stop/kill/volume rm on containers or volumes whose name
#              contains prod, production, or live.
#
# Config (env vars):
#   CLAUDE_ALLOW_DOCKER_PROD=1   Bypass the gate. Default: gate enforced.
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
#               "command": "/path/to/hooks/devops/docker-prod-guard.sh"
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

# Only care about docker commands
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]])docker[[:space:]]'; then
  exit 0
fi

block() {
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "docker command targets production container/volume. Set CLAUDE_ALLOW_DOCKER_PROD=1 to allow."
    }
  }'
  exit 0
}

if [[ "${CLAUDE_ALLOW_DOCKER_PROD:-}" == "1" ]]; then
  exit 0
fi

# Readonly commands — always allow
if echo "$COMMAND" | grep -qE '(^|[[:space:]])docker[[:space:]]+(ps|logs|inspect|stats|top|diff|port|events|info|version|images|network[[:space:]]+inspect|volume[[:space:]]+inspect)([[:space:]]|$)'; then
  exit 0
fi

# Dangerous docker subcommands to check
DANGEROUS_SUBCMD_PATTERN='(rm|stop|kill|restart|pause|unpause|exec|cp|rename|update|prune)'

if ! echo "$COMMAND" | grep -qE "(^|[[:space:]])docker[[:space:]]+(${DANGEROUS_SUBCMD_PATTERN}|volume[[:space:]]+rm|compose[[:space:]]+(down|rm|stop|kill))[[:space:]]"; then
  exit 0
fi

# Check if any argument looks like a prod container/volume name
PROD_NAME_PATTERN='(prod|production|live)'

# Extract everything after the subcommand as potential target names
TARGETS=$(echo "$COMMAND" | sed 's/.*docker[[:space:]][[:space:]]*//' | sed 's/^[^[:space:]]*//' )

if echo "$TARGETS" | grep -qiE "$PROD_NAME_PATTERN"; then
  block
fi

# Also check docker-compose down with a prod-named compose file or project
if echo "$COMMAND" | grep -qE 'docker[[:space:]]+(compose|--compose)[[:space:]]+(down|stop|rm)'; then
  if echo "$COMMAND" | grep -qiE "\-p[[:space:]]*${PROD_NAME_PATTERN}|--project-name[[:space:]]*${PROD_NAME_PATTERN}|\-f[[:space:]]*[^[:space:]]*(prod|production|live)[^[:space:]]*"; then
    block
  fi
fi

exit 0
