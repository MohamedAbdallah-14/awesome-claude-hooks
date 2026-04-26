#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

CWD=$(jq -r '.cwd // empty' <<< "$INPUT")
CWD="${CWD:-$PWD}"

if ! git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  exit 0
fi

BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")

if [[ -z "$BRANCH" || "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  exit 0
fi

# Replace path separators and hyphens with spaces, then title-case each word
TITLE=$(echo "$BRANCH" \
  | tr '/_-' ' ' \
  | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')

jq -n --arg title "Session: $TITLE" '{"additionalContext": $title}'
