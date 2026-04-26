#!/usr/bin/env bash
# PreToolUse | Bash
# Blocks kubectl commands targeting production clusters or namespaces.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT")

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only care about kubectl commands
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]])kubectl[[:space:]]'; then
  exit 0
fi

block() {
  printf '{"decision":"block","reason":"kubectl command targets production cluster. Set CLAUDE_ALLOW_K8S_PROD=1 to allow."}'
  exit 2
}

if [[ "${CLAUDE_ALLOW_K8S_PROD:-}" == "1" ]]; then
  exit 0
fi

# Check for explicit namespace flags: --namespace production, -n prod, -n production
if echo "$COMMAND" | grep -qE '(\-\-namespace[[:space:]]+production|[[:space:]]\-n[[:space:]]+(prod|production))([[:space:]]|$)'; then
  block
fi

# Check for --context flag targeting prod contexts inline in the command
if echo "$COMMAND" | grep -qE '\-\-context[[:space:]]+[^[:space:]]*(prod|production|prd)[^[:space:]]*'; then
  block
fi

# Check the live current-context via kubectl config
# Only do this if kubectl is actually on PATH and config exists
if command -v kubectl &>/dev/null; then
  CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
  if [[ -n "$CURRENT_CONTEXT" ]]; then
    if echo "$CURRENT_CONTEXT" | grep -qiE '(prod|production|prd)'; then
      block
    fi
  fi
fi

# Block kubectl delete without any namespace flag (could hit default in prod context)
if echo "$COMMAND" | grep -qE '(^|[[:space:]])kubectl[[:space:]]+(.*[[:space:]])?delete[[:space:]]'; then
  if ! echo "$COMMAND" | grep -qE '(\-\-namespace|\-n[[:space:]])'; then
    # Only block if no namespace scoping is present — risky command
    printf '{"decision":"block","reason":"kubectl delete without explicit --namespace flag. Set CLAUDE_ALLOW_K8S_PROD=1 to allow, or add -n <namespace> to scope the command."}'
    exit 2
  fi
fi

exit 0
