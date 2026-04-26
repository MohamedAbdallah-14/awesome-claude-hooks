#!/usr/bin/env bash
# Hook name:   banned-words-enforcer
# Event:       UserPromptSubmit
# Description: Reads banned words/phrases from ~/.claude/banned-words.txt
#              (one entry per line, case-insensitive). If any appear in the
#              user's prompt, appends a reminder to Claude to avoid them in
#              its response. Additive — never modifies the original request.
#              If the file does not exist, the hook exits silently.
#
# banned-words.txt format (one word or phrase per line, # for comments):
#   leverage
#   synergy
#   utilize
#   circle back
#   # this line is a comment and will be ignored
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "UserPromptSubmit": [
#         {
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/prompt/banned-words-enforcer.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

BANNED_FILE="${HOME}/.claude/banned-words.txt"

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[banned-words-enforcer] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── skip if no banned-words file ─────────────────────────────────────────────

if [[ ! -f "$BANNED_FILE" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

ORIGINAL_PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""')

if [[ -z "$ORIGINAL_PROMPT" ]]; then
  exit 0
fi

LOWER_PROMPT=$(printf '%s' "$ORIGINAL_PROMPT" | tr '[:upper:]' '[:lower:]')

# ── scan for matches ──────────────────────────────────────────────────────────

declare -a MATCHED=()

while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip blank lines and comments
  [[ -z "$line" || "$line" == \#* ]] && continue
  WORD=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' | xargs)
  [[ -z "$WORD" ]] && continue
  if [[ "$LOWER_PROMPT" == *"$WORD"* ]]; then
    MATCHED+=("$line")
  fi
done < "$BANNED_FILE"

if [[ ${#MATCHED[@]} -eq 0 ]]; then
  exit 0
fi

# ── build reminder and append ─────────────────────────────────────────────────

WORD_LIST=$(IFS=", "; echo "${MATCHED[*]}")
REMINDER=$'\n\nNote: Avoid these words in your response: '"${WORD_LIST}."

UPDATED_PROMPT="${ORIGINAL_PROMPT}${REMINDER}"

jq -n --arg p "$UPDATED_PROMPT" '{"hookSpecificOutput":{"updatedPrompt":$p}}'
