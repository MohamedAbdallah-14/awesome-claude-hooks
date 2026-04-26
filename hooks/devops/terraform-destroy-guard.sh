#!/usr/bin/env bash
# PreToolUse | Bash
# Blocks terraform destroy unless CLAUDE_ALLOW_DESTROY=1 is set.
# Warns (but allows) on terraform apply -destroy.

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
  printf '{"decision":"block","reason":"terraform destroy blocked. Set CLAUDE_ALLOW_DESTROY=1 to allow destructive infra changes."}'
  exit 2
fi

# Warn (but allow): terraform apply -destroy
if echo "$COMMAND" | grep -qE 'terraform[[:space:]]+(.*[[:space:]])?apply' && \
   echo "$COMMAND" | grep -q -- '-destroy'; then
  if [[ "${CLAUDE_ALLOW_DESTROY:-}" == "1" ]]; then
    exit 0
  fi
  # Log the warning to stderr; still allow by exiting 0
  printf '{"decision":"block","reason":"terraform apply -destroy blocked. Set CLAUDE_ALLOW_DESTROY=1 to allow destructive infra changes."}' >&2
  # Allow — warn only
  exit 0
fi

exit 0
