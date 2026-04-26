#!/usr/bin/env bash
# Hook name:   session-context-injector
# Event:       UserPromptSubmit
# Description: Prepends a compact one-line context header to every user prompt.
#              Header includes current git branch and whether a CLAUDE.md exists
#              in the working directory. Keeps the prefix under 100 chars.
#
#   Examples:
#     [branch:main | CLAUDE.md:yes] fix the auth bug
#     [branch:feature/login] add unit tests
#     [CLAUDE.md:yes] what does this file do?
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
#               "command": "/path/to/hooks/prompt/session-context-injector.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[session-context-injector] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

ORIGINAL_PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""')
CWD="${CWD:-$PWD}"

if [[ -z "$ORIGINAL_PROMPT" ]]; then
  exit 0
fi

# ── gather context ────────────────────────────────────────────────────────────

BRANCH=""
if git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
fi

CLAUDE_MD=""
if [[ -f "$CWD/CLAUDE.md" ]]; then
  CLAUDE_MD="yes"
fi

# ── build prefix ─────────────────────────────────────────────────────────────

PARTS=()
[[ -n "$BRANCH" ]]     && PARTS+=("branch:${BRANCH}")
[[ -n "$CLAUDE_MD" ]]  && PARTS+=("CLAUDE.md:yes")

if [[ ${#PARTS[@]} -eq 0 ]]; then
  exit 0
fi

# Join parts with " | " and wrap in brackets
PREFIX="[$(IFS=" | "; echo "${PARTS[*]}")]"

UPDATED_PROMPT="${PREFIX} ${ORIGINAL_PROMPT}"

# ── emit ──────────────────────────────────────────────────────────────────────

jq -n --arg p "$UPDATED_PROMPT" '{"hookSpecificOutput":{"updatedPrompt":$p}}'
