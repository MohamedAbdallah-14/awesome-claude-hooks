#!/usr/bin/env bash
# PreToolUse | Write
# Validates YAML syntax of GitHub Actions workflow files before they are written.
# Fires on Write tool calls; payload has tool_input.path and tool_input.content.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

FILE_PATH=$(jq -r '.tool_input.path // empty' <<< "$INPUT")

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only care about .github/workflows/*.yml or *.yaml
if ! echo "$FILE_PATH" | grep -qE '\.github/workflows/[^/]+\.ya?ml$'; then
  exit 0
fi

# Check python3 and yaml module availability; skip gracefully if missing
if ! command -v python3 &>/dev/null; then
  exit 0
fi

if ! python3 -c "import yaml" 2>/dev/null; then
  # PyYAML not installed; skip validation rather than false-blocking
  exit 0
fi

# Extract the content to be written
CONTENT=$(jq -r '.tool_input.content // empty' <<< "$INPUT")

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Write content to a temp file for validation
TMPFILE=$(mktemp /tmp/gh-actions-validate-XXXXXX.yml)
# Ensure cleanup on exit
trap 'rm -f "$TMPFILE"' EXIT

printf '%s' "$CONTENT" > "$TMPFILE"

# Run YAML validation
YAML_ERROR=$(python3 -c "
import yaml, sys
try:
    with open('${TMPFILE}', 'r') as f:
        yaml.safe_load(f)
    sys.exit(0)
except yaml.YAMLError as e:
    print(str(e))
    sys.exit(1)
" 2>&1) || {
  # Escape double quotes in error for valid JSON
  SAFE_ERROR=$(printf '%s' "$YAML_ERROR" | tr '"' "'" | tr '\n' ' ')
  printf '{"decision":"block","reason":"GitHub Actions workflow has invalid YAML: %s"}' "$SAFE_ERROR"
  exit 2
}

exit 0
