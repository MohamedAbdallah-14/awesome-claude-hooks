#!/usr/bin/env bash
# Hook name:   inject-package-info
# Event:       PreToolUse
# Matcher:     Edit|Write|MultiEdit
# Description: When Claude is about to edit a dependency manifest
#              (package.json, pubspec.yaml, requirements.txt, go.mod),
#              inject a human-readable summary of the current package
#              state so Claude understands what's already declared before
#              adding or modifying dependencies.
#
# Supported formats:
#   package.json    → name, version, top 10 deps + devDeps
#   pubspec.yaml    → name, version, dependencies block
#   requirements.txt → line count + first 20 entries
#   go.mod          → module name, go version, first 10 require entries
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Edit|Write|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/context/inject-package-info.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────

approve() { printf '{"decision":"approve"}\n'; exit 0; }

approve_with_context() {
  local ctx="$1"
  jq -n --arg c "$ctx" '{"decision":"approve","context":$c}'
  exit 0
}

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  approve
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  approve
fi

TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r '.tool_input // {}')

FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '
  if type == "object" then
    (.file_path // (.edits[0].file_path? // "") // "")
  else ""
  end
' 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]]; then
  approve
fi

# Resolve to absolute path
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="${PWD}/${FILE_PATH}"
fi

BASENAME=$(basename "$FILE_PATH")

# ── filter: only act on manifest files ───────────────────────────────────────

case "$BASENAME" in
  package.json|pubspec.yaml|requirements.txt|go.mod)
    ;;
  *)
    approve
    ;;
esac

# File must exist to summarise it
if [[ ! -f "$FILE_PATH" ]]; then
  # New file being created — no existing state to summarise
  approve
fi

# ── parse and summarise ───────────────────────────────────────────────────────

CONTEXT=""

case "$BASENAME" in

  package.json)
    PKG_NAME=$(jq -r '.name // "(unnamed)"' "$FILE_PATH" 2>/dev/null || echo "unknown")
    PKG_VERSION=$(jq -r '.version // "(no version)"' "$FILE_PATH" 2>/dev/null || echo "unknown")

    DEPS=$(jq -r '
      (.dependencies // {}) | to_entries
      | sort_by(.key)
      | .[:10]
      | map("  \(.key): \(.value)")
      | join("\n")
    ' "$FILE_PATH" 2>/dev/null || echo "  (none)")
    DEPS_COUNT=$(jq -r '(.dependencies // {}) | length' "$FILE_PATH" 2>/dev/null || echo "0")

    DEV_DEPS=$(jq -r '
      (.devDependencies // {}) | to_entries
      | sort_by(.key)
      | .[:10]
      | map("  \(.key): \(.value)")
      | join("\n")
    ' "$FILE_PATH" 2>/dev/null || echo "  (none)")
    DEV_DEPS_COUNT=$(jq -r '(.devDependencies // {}) | length' "$FILE_PATH" 2>/dev/null || echo "0")

    CONTEXT="Current package.json for \`${PKG_NAME}@${PKG_VERSION}\`:\n\ndependencies (${DEPS_COUNT} total, showing first 10):\n${DEPS}\n\ndevDependencies (${DEV_DEPS_COUNT} total, showing first 10):\n${DEV_DEPS}"
    ;;

  pubspec.yaml)
    # pubspec.yaml is YAML — parse with grep/awk since yq isn't guaranteed
    PUBSPEC_NAME=$(grep -E '^name:' "$FILE_PATH" | head -1 | sed 's/name:[[:space:]]*//' | tr -d '"' || echo "unknown")
    PUBSPEC_VERSION=$(grep -E '^version:' "$FILE_PATH" | head -1 | sed 's/version:[[:space:]]*//' | tr -d '"' || echo "unknown")

    # Extract the dependencies block (lines between "dependencies:" and next top-level key or EOF)
    DEPS_BLOCK=$(awk '/^dependencies:/{found=1; next} found && /^[a-zA-Z]/{exit} found{print}' "$FILE_PATH" | head -20 || echo "  (could not parse)")
    DEV_DEPS_BLOCK=$(awk '/^dev_dependencies:/{found=1; next} found && /^[a-zA-Z]/{exit} found{print}' "$FILE_PATH" | head -20 || echo "  (none)")

    CONTEXT="Current pubspec.yaml for \`${PUBSPEC_NAME} ${PUBSPEC_VERSION}\`:\n\ndependencies:\n${DEPS_BLOCK}\n\ndev_dependencies:\n${DEV_DEPS_BLOCK}"
    ;;

  requirements.txt)
    TOTAL_LINES=$(grep -c '.' "$FILE_PATH" 2>/dev/null || echo "0")
    # Skip comment and blank lines for the count
    DEP_COUNT=$(grep -cvE '^[[:space:]]*(#|$)' "$FILE_PATH" 2>/dev/null || echo "0")
    FIRST_DEPS=$(grep -vE '^[[:space:]]*(#|$)' "$FILE_PATH" 2>/dev/null | head -20 || echo "(empty)")

    CONTEXT="Current requirements.txt: ${DEP_COUNT} dependencies (${TOTAL_LINES} total lines).\n\nFirst 20 entries:\n\`\`\`\n${FIRST_DEPS}\n\`\`\`"
    ;;

  go.mod)
    MODULE_NAME=$(grep -E '^module ' "$FILE_PATH" | head -1 | awk '{print $2}' || echo "unknown")
    GO_VERSION=$(grep -E '^go ' "$FILE_PATH" | head -1 | awk '{print $2}' || echo "unknown")
    REQUIRES=$(awk '/^require \(/{found=1; next} /^\)/{found=0} found{print}' "$FILE_PATH" | head -10 | sed 's/^\t/  /' || true)
    # Also handle single-line require
    SINGLE_REQUIRES=$(grep -E '^require [^(]' "$FILE_PATH" | head -10 | sed 's/^require /  /' || true)
    ALL_REQUIRES="${REQUIRES}${SINGLE_REQUIRES}"
    REQ_COUNT=$(grep -cE '^\s+[a-z]' "$FILE_PATH" 2>/dev/null || echo "?")

    CONTEXT="Current go.mod:\n  module: ${MODULE_NAME}\n  go: ${GO_VERSION}\n\nrequire (${REQ_COUNT} entries, first 10):\n\`\`\`\n${ALL_REQUIRES}\n\`\`\`"
    ;;
esac

if [[ -z "$CONTEXT" ]]; then
  approve
fi

approve_with_context "$CONTEXT"
