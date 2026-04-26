#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   session-start-context
# Event:       SessionStart
# Description: Injects useful project context at session start: current branch, recent commits, modified files, and any project notes.
#
set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

CWD=$(jq -r '.cwd // empty' <<< "$INPUT")
CWD="${CWD:-$PWD}"

DIR_NAME=$(basename "$CWD")

BRANCH=""
COMMITS=""
if git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
  COMMITS=$(git -C "$CWD" log --oneline -3 2>/dev/null | sed 's/"/\\"/g' | awk '{printf "    - %s\\n", $0}' || echo "")
fi

NOTES=""
for candidate in "$CWD/TODO.md" "$CWD/.notes.md"; do
  if [[ -f "$candidate" ]]; then
    NOTE_CONTENT=$(head -20 "$candidate" 2>/dev/null | sed 's/"/\\"/g' | awk '{printf "    %s\\n", $0}')
    FNAME=$(basename "$candidate")
    NOTES="${NOTES}  - ${FNAME}:\\n${NOTE_CONTENT}"
  fi
done

CONTEXT="Session context:\\n- Directory: ${DIR_NAME}"

if [[ -n "$BRANCH" ]]; then
  CONTEXT="${CONTEXT}\\n- Branch: ${BRANCH}"
fi

if [[ -n "$COMMITS" ]]; then
  CONTEXT="${CONTEXT}\\n- Recent commits:\\n${COMMITS}"
fi

if [[ -n "$NOTES" ]]; then
  CONTEXT="${CONTEXT}\\n- Notes:\\n${NOTES}"
fi

jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
