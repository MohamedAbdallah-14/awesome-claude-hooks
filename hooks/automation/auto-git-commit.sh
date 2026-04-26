#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   auto-git-commit
# Event:       Stop
# Description: When Claude's session ends, stages all modified tracked files
#              and commits them. Commit message is derived from Claude's last
#              response in the transcript, prefixed with "claude:".
#
#              Safety guards:
#                - Off by default (must set CLAUDE_AUTO_COMMIT=1)
#                - Skips if no changes are present
#                - Never commits on protected branches (main, master by default)
#                - Never commits if git is not available or cwd is not a repo
#
# Config (env vars):
#   CLAUDE_AUTO_COMMIT=0                    Set to 1 to enable (opt-in, default OFF).
#   CLAUDE_AUTO_COMMIT_BRANCH_PROTECTION    Space-separated branch names to skip.
#                                           Default: "main master"
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "matcher": "",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/automation/auto-git-commit.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── opt-in gate ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_AUTO_COMMIT:-0}" != "1" ]]; then
  exit 0
fi

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-git-commit] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

if ! command -v git &>/dev/null; then
  echo "[auto-git-commit] WARNING: git not found — skipping commit" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')

# ── git repo check ────────────────────────────────────────────────────────────

if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  echo "[auto-git-commit] Not inside a git repo — skipping" >&2
  exit 0
fi

# ── branch protection ─────────────────────────────────────────────────────────

PROTECTED_BRANCHES="${CLAUDE_AUTO_COMMIT_BRANCH_PROTECTION:-main master}"
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "HEAD")

for PROTECTED in $PROTECTED_BRANCHES; do
  if [[ "$CURRENT_BRANCH" == "$PROTECTED" ]]; then
    echo "[auto-git-commit] Skipping commit — on protected branch: $CURRENT_BRANCH" >&2
    exit 0
  fi
done

# ── check for changes ─────────────────────────────────────────────────────────

# Stage all tracked modified/deleted files (not untracked — auto-adding unknown
# files is too aggressive and could leak secrets)
git add --update

STAGED_COUNT=$(git diff --cached --name-only | wc -l | tr -d ' ')
if [[ "$STAGED_COUNT" -eq 0 ]]; then
  echo "[auto-git-commit] No staged changes — nothing to commit"
  exit 0
fi

# ── build commit message ──────────────────────────────────────────────────────

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMIT_MSG="claude: automated changes $TIMESTAMP"

# try to extract a meaningful summary from the transcript
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  # transcript is JSONL — find the last assistant message and grab its text
  LAST_ASSISTANT_TEXT=$(jq -r 'select(.role == "assistant") | .content' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || true)

  # content may be a string or an array of blocks
  if [[ -n "$LAST_ASSISTANT_TEXT" && "$LAST_ASSISTANT_TEXT" != "null" ]]; then
    # if it's a JSON array, extract the first text block
    if printf '%s' "$LAST_ASSISTANT_TEXT" | jq -e 'type == "array"' &>/dev/null 2>&1; then
      SUMMARY=$(printf '%s' "$LAST_ASSISTANT_TEXT" | jq -r '[.[] | select(.type == "text") | .text] | first // ""' 2>/dev/null || true)
    else
      SUMMARY="$LAST_ASSISTANT_TEXT"
    fi

    if [[ -n "$SUMMARY" && "$SUMMARY" != "null" ]]; then
      # take first line, strip markdown noise, truncate to 60 chars
      FIRST_LINE=$(printf '%s' "$SUMMARY" | head -1 | sed 's/^[#* ]*//;s/[`*_]//g')
      if [[ -n "$FIRST_LINE" ]]; then
        COMMIT_MSG="claude: ${FIRST_LINE:0:60}"
      fi
    fi
  fi
fi

# ── commit ────────────────────────────────────────────────────────────────────

echo "[auto-git-commit] Committing $STAGED_COUNT file(s) on branch $CURRENT_BRANCH"
echo "[auto-git-commit] Message: $COMMIT_MSG"

COMMIT_EXIT=0
git commit -m "$COMMIT_MSG" 2>&1 || COMMIT_EXIT=$?

if [[ $COMMIT_EXIT -eq 0 ]]; then
  COMMIT_HASH=$(git rev-parse --short HEAD)
  echo "[auto-git-commit] Committed as $COMMIT_HASH"
else
  echo "[auto-git-commit] WARNING: git commit failed (exit $COMMIT_EXIT)" >&2
fi

exit 0
