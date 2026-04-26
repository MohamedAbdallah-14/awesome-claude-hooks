#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   env-file-injector
# Event:       SessionStart
# Description: Loads .claude.env from the repo root and injects key=value pairs as session context. Redacts values that look like real secrets.
#
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "SessionStart": [
#         {
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/session/env-file-injector.sh"
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

CWD=$(jq -r '.cwd // empty' <<< "$INPUT")
CWD="${CWD:-$PWD}"

ENV_FILE="${CWD}/.claude.env"

if [[ ! -f "$ENV_FILE" ]]; then
  exit 0
fi

LINES=""
WARNED=0

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^# ]] && continue
  [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue

  KEY="${line%%=*}"
  VALUE="${line#*=}"

  # Warn and redact values that look like real credentials
  if echo "$VALUE" | grep -qE '(^sk-|^AKIA[0-9A-Z]{16}|^ghp_)'; then
    LINES="${LINES}${KEY}=<redacted — possible secret detected>\\n"
    WARNED=1
  else
    SAFE_VALUE=$(echo "$VALUE" | sed 's/"/\\"/g')
    LINES="${LINES}${KEY}=${SAFE_VALUE}\\n"
  fi
done < "$ENV_FILE"

if [[ -z "$LINES" ]]; then
  exit 0
fi

PREFIX=".claude.env loaded:"
if [[ "$WARNED" -eq 1 ]]; then
  PREFIX="⚠ .claude.env loaded (one or more values redacted — looks like real secrets):"
fi

jq -n --arg ctx "${PREFIX}\\n${LINES}" '{"additionalContext": $ctx}'
