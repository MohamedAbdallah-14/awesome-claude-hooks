#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   terraform-destroy-guard
# Event:       PreToolUse (matcher: "Bash")
# Description: Blocks terraform destroy unless CLAUDE_ALLOW_DESTROY=1 is set.
#              Warns (but allows) on terraform apply -destroy.
#
# Config (env vars):
#   CLAUDE_ALLOW_DESTROY=1   Bypass the gate. Default: gate enforced.
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
#               "command": "/path/to/hooks/devops/terraform-destroy-guard.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

INPUT=$(cat)

# Graceful fallback if jq is missing
if ! command -v jq &>/dev/null; then
  exit 0
fi

COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT")

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Check for terraform in the command
if ! echo "$COMMAND" | grep -q 'terraform'; then
  exit 0
fi

# Block: terraform destroy (any form)
if echo "$COMMAND" | grep -qE 'terraform[[:space:]]+(.*[[:space:]])?destroy'; then
  if [[ "${CLAUDE_ALLOW_DESTROY:-}" == "1" ]]; then
    exit 0
  fi
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "terraform destroy blocked. Set CLAUDE_ALLOW_DESTROY=1 to allow destructive infra changes."
    }
  }'
  exit 0
fi

# Warn (but allow): terraform apply -destroy
if echo "$COMMAND" | grep -qE 'terraform[[:space:]]+(.*[[:space:]])?apply' && \
   echo "$COMMAND" | grep -q -- '-destroy'; then
  if [[ "${CLAUDE_ALLOW_DESTROY:-}" == "1" ]]; then
    exit 0
  fi
  # Plain stderr warning — exit 0 means stderr is logged, not surfaced as
  # a decision. The action proceeds.
  echo "[terraform-destroy-guard] WARNING: terraform apply -destroy detected. Set CLAUDE_ALLOW_DESTROY=1 to silence." >&2
  exit 0
fi

exit 0
