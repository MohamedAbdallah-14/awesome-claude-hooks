#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   context-threshold-guard
# Event:       UserPromptSubmit
# Description: Warns when transcript size grows past a threshold so the user can /compact.
#
set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

TRANSCRIPT=$(jq -r '.transcript_path // empty' <<< "$INPUT")

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

LINE_COUNT=$(wc -l < "$TRANSCRIPT" | tr -d ' ')

THRESHOLD=2000
if [[ "$LINE_COUNT" -le "$THRESHOLD" ]]; then
  exit 0
fi

MSG="⚠ Context is large (${LINE_COUNT} lines). Consider /compact or starting a new session for best results."

jq -n --arg msg "$MSG" '{"additionalContext": $msg}'
