#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   no-ask-human-blocker
# Event:       UserPromptSubmit
# Description: Detects when the user instructs Claude not to ask questions
#              ("don't ask", "no questions", "just do it", "without asking",
#              "autonomously") and reinforces that intent by appending an
#              explicit instruction to the prompt. This ensures Claude honours
#              the user's preference even if it would normally pause to clarify.
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
#               "command": "/path/to/hooks/prompt/no-ask-human-blocker.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[no-ask-human-blocker] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

ORIGINAL_PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""')

if [[ -z "$ORIGINAL_PROMPT" ]]; then
  exit 0
fi

# ── trigger phrase detection ──────────────────────────────────────────────────

LOWER_PROMPT=$(printf '%s' "$ORIGINAL_PROMPT" | tr '[:upper:]' '[:lower:]')

TRIGGERED=0
for phrase in "don't ask" "dont ask" "no questions" "just do it" "without asking" "autonomously"; do
  if [[ "$LOWER_PROMPT" == *"$phrase"* ]]; then
    TRIGGERED=1
    break
  fi
done

if [[ "$TRIGGERED" -eq 0 ]]; then
  exit 0
fi

# ── append reinforcement ──────────────────────────────────────────────────────

SUFFIX=$'\n\nIMPORTANT: Proceed autonomously. Make reasonable decisions without asking clarifying questions.'

UPDATED_PROMPT="${ORIGINAL_PROMPT}${SUFFIX}"

jq -n --arg p "$UPDATED_PROMPT" '{"hookSpecificOutput":{"updatedPrompt":$p}}'
