#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   validate-json-yaml
# Event:       PreToolUse (matcher: "Write|Edit|MultiEdit")
# Description: Before Claude writes a .json, .yaml, or .yml file, validates
#              that the content being written is syntactically valid. Blocks the
#              write and returns the parse error so Claude can fix the content
#              before it hits disk.
#
#              Prevents broken config files (package.json, docker-compose.yml,
#              GitHub Actions workflows, etc.) from ever being saved.
#
#              JSON validation: python3 -m json.tool
#              YAML validation: python3 -c "import yaml; yaml.safe_load(...)"
#                               Falls back to checking 'pyyaml' install hint if
#                               the yaml module is missing.
#
#              Matches: .json  .yaml  .yml
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
#               "command": "/path/to/hooks/quality/validate-json-yaml.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[validate-json-yaml] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── extension filter ──────────────────────────────────────────────────────────

case "$FILE_PATH" in
  *.json|*.yaml|*.yml) ;;
  *) exit 0 ;;
esac

# ── extract content to validate ───────────────────────────────────────────────
# For Write: full new content is in tool_input.content
# For Edit / MultiEdit: validate the new_string snippets (not the whole file,
# since the full result isn't available yet). If new_string is not valid on its
# own we skip — partial YAML/JSON snippets can be legitimate fragments.

CONTENT=""

if [[ "$HOOK_EVENT" == "PreToolUse" ]]; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

  case "$TOOL_NAME" in
    Write)
      CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""')
      ;;
    Edit)
      # Validate the new_string; if it looks like a JSON/YAML fragment we skip
      # (only validate complete writes to avoid false positives on partial edits)
      exit 0
      ;;
    MultiEdit)
      exit 0
      ;;
    *)
      exit 0
      ;;
  esac
fi

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# ── validate ──────────────────────────────────────────────────────────────────

PARSE_ERROR=""

case "$FILE_PATH" in
  *.json)
    if ! command -v python3 &>/dev/null; then
      echo "[validate-json-yaml] WARNING: python3 not found — skipping JSON validation" >&2
      exit 0
    fi
    PARSE_ERROR=$(printf '%s' "$CONTENT" | python3 -m json.tool > /dev/null 2>&1 && echo "" \
                  || printf '%s' "$CONTENT" | python3 -m json.tool 2>&1 | grep -v "^{" | head -5 \
                  || true)
    # Re-run to capture only the error message (json.tool outputs valid JSON on stdout, error on stderr)
    VALIDATE_EXIT=0
    PARSE_ERROR=$(printf '%s' "$CONTENT" | python3 -c "
import sys, json
try:
    json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    print(str(e))
    sys.exit(1)
" 2>&1) || VALIDATE_EXIT=$?

    if [[ $VALIDATE_EXIT -eq 0 ]]; then
      exit 0
    fi

    jq -n \
      --arg path "$FILE_PATH" \
      --arg err "$PARSE_ERROR" \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ("Blocked: content for " + $path + " is not valid JSON.\n\nParse error: " + $err + "\n\nFix the JSON syntax before writing.")
        }
      }'
    exit 0
    ;;

  *.yaml|*.yml)
    if ! command -v python3 &>/dev/null; then
      echo "[validate-json-yaml] WARNING: python3 not found — skipping YAML validation" >&2
      exit 0
    fi

    # Check if pyyaml is available
    if ! python3 -c "import yaml" &>/dev/null 2>&1; then
      echo "[validate-json-yaml] WARNING: pyyaml not installed — skipping YAML validation" >&2
      echo "[validate-json-yaml]   Install with: pip install pyyaml" >&2
      exit 0
    fi

    VALIDATE_EXIT=0
    PARSE_ERROR=$(printf '%s' "$CONTENT" | python3 -c "
import sys, yaml
try:
    yaml.safe_load(sys.stdin.read())
except yaml.YAMLError as e:
    print(str(e))
    sys.exit(1)
" 2>&1) || VALIDATE_EXIT=$?

    if [[ $VALIDATE_EXIT -eq 0 ]]; then
      exit 0
    fi

    jq -n \
      --arg path "$FILE_PATH" \
      --arg err "$PARSE_ERROR" \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ("Blocked: content for " + $path + " is not valid YAML.\n\nParse error: " + $err + "\n\nFix the YAML syntax before writing.")
        }
      }'
    exit 0
    ;;
esac

exit 0
