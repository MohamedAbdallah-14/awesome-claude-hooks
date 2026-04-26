#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   session-summary
# Event:       Stop
# Description: Appends a one-line summary of the session (start time, cwd, tool call count) to a daily markdown log.
#
set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

CWD=$(jq -r '.cwd // empty' <<< "$INPUT")
CWD="${CWD:-$PWD}"

TRANSCRIPT=$(jq -r '.transcript_path // empty' <<< "$INPUT")

TOOL_CALLS=0
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  # Each tool call in the JSONL transcript has a "type":"tool_use" entry
  TOOL_CALLS=$(grep -c '"type":"tool_use"' "$TRANSCRIPT" 2>/dev/null || echo 0)
fi

SESSIONS_DIR="$HOME/.claude/sessions"
mkdir -p "$SESSIONS_DIR"

LOG_FILE="${SESSIONS_DIR}/$(date +%Y-%m-%d).md"
TIMESTAMP=$(date +%H:%M:%S)

printf -- "- %s | %s | %d tool calls\n" "$TIMESTAMP" "$CWD" "$TOOL_CALLS" >> "$LOG_FILE"
