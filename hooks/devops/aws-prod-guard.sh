#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   aws-prod-guard
# Event:       PreToolUse (matcher: "Bash")
# Description: Blocks destructive AWS CLI commands targeting production profiles.
#
# Config (env vars):
#   CLAUDE_ALLOW_AWS_PROD=1   Bypass the gate. Default: gate enforced.
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
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

if [[ "${CLAUDE_ALLOW_AWS_PROD:-}" == "1" ]]; then
  exit 0
fi

# Readonly subcommand verbs. Must come right after `aws <service>` to count
# as readonly — otherwise a trailing token like `--user-name test` could be
# misread as a readonly verb. Dropped `test`/`validate`/`preview`/`estimate`/
# `forecast`/`explain` from the list because those names also appear as
# non-readonly trailing arg values.
READONLY_VERBS='(describe|list|get|ls|head|lookup|scan|query|search|show)'

# Split COMMAND on shell separators (;, &&, ||, |, &) and ensure EVERY aws
# invocation is readonly before short-circuiting. Otherwise a chain like
# `aws s3 ls && aws s3 rm s3://prod-bucket/data` would be allowed because
# the first segment looks readonly.
ALL_AWS_READONLY=1
ANY_AWS_SEEN=0
# Use awk to split on the multi-char separators; tr collapses single-char ones.
SEGMENTS=$(printf '%s' "$COMMAND" | awk '{
  gsub(/&&|\|\||;|\||&/, "\n");
  print
}')
while IFS= read -r segment; do
  # Only consider segments that actually invoke aws.
  if echo "$segment" | grep -qE '(^|[[:space:]])aws[[:space:]]'; then
    ANY_AWS_SEEN=1
    if ! echo "$segment" | grep -qE "(^|[[:space:]])aws[[:space:]]+[[:alnum:]_-]+[[:space:]]+${READONLY_VERBS}([-_[:alnum:]]+)?([[:space:]]|$)"; then
      ALL_AWS_READONLY=0
      break
    fi
  fi
done <<< "$SEGMENTS"

if [[ "$ANY_AWS_SEEN" -eq 1 && "$ALL_AWS_READONLY" -eq 1 ]]; then
  exit 0
fi

# Detect production profile: --profile prod*, AWS_PROFILE=prod*, AWS_DEFAULT_PROFILE=prod*.
# Character class places `-` last so BSD grep doesn't read it as a range.
TARGETS_PROD=0

if echo "$COMMAND" | grep -qE '\-\-profile[[:space:]]+prod[[:alnum:]_-]*'; then
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
