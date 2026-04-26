#!/usr/bin/env bash
# PostToolUse | Bash
# Silently logs infrastructure commands (terraform, kubectl, aws, gcloud, helm, docker)
# to ~/.claude/infra-audit.log. Always exits 0.

set -euo pipefail

INPUT=$(cat)

# Never block — always allow
allow_and_exit() {
  exit 0
}

if ! command -v jq &>/dev/null; then
  allow_and_exit
fi

COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT")

if [[ -z "$COMMAND" ]]; then
  allow_and_exit
fi

# Match infra-related commands
INFRA_PATTERN='(terraform|kubectl|aws|gcloud|gsutil|helm|docker|docker-compose|az|vault|consul|ansible|packer|pulumi|cdk)'

if ! echo "$COMMAND" | grep -qE "(^|[[:space:]])${INFRA_PATTERN}[[:space:]]"; then
  allow_and_exit
fi

# Build log entry
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CWD=$(pwd 2>/dev/null || echo "unknown")

# Sanitize command for single-line log: collapse whitespace, strip newlines
SAFE_CMD=$(printf '%s' "$COMMAND" | tr '\n' ' ' | tr '\t' ' ')

LOG_DIR="${HOME}/.claude"
LOG_FILE="${LOG_DIR}/infra-audit.log"

# Create log directory if needed
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Append log entry; silently ignore write errors (e.g., read-only fs)
printf '%s | %s | %s\n' "$TIMESTAMP" "$CWD" "$SAFE_CMD" >> "$LOG_FILE" 2>/dev/null || true

allow_and_exit
