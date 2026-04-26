#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   inject-git-context
# Event:       Stop
# Description: After each response, writes a git context summary to
#              ~/.claude/context/git-status.md so Claude has up-to-date
#              repo state at the start of the next turn.
#              Captures: current branch, short status, last 3 commits,
#              and any merge conflict markers.
#
# Config (env vars):
#   CLAUDE_GIT_CONTEXT_MAX_FILES   Max lines of `git status --short` to
#                                  capture. Default: 50.
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
#               "command": "/path/to/hooks/context/inject-git-context.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v git &>/dev/null; then
  echo "[inject-git-context] WARNING: git not found — skipping" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[inject-git-context] WARNING: jq not found — skipping" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

MAX_FILES="${CLAUDE_GIT_CONTEXT_MAX_FILES:-50}"
CONTEXT_DIR="${HOME}/.claude/context"
OUTPUT_FILE="${CONTEXT_DIR}/git-status.md"

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
# Stop hooks carry stop_hook_active; just consume it — we don't need values here
# Validate it is parseable JSON so we don't run on garbage input
if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  echo "[inject-git-context] WARNING: invalid JSON on stdin — skipping" >&2
  exit 0
fi

# ── check we are inside a git repo ───────────────────────────────────────────

if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  # Not a git repo — write a minimal note so Claude doesn't get stale context
  mkdir -p "$CONTEXT_DIR"
  printf '# Git Context\n\nNot a git repository (as of %s).\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$OUTPUT_FILE"
  exit 0
fi

# ── gather git data ───────────────────────────────────────────────────────────

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "detached")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Short status, capped to MAX_FILES lines
STATUS_OUTPUT=$(git status --short 2>/dev/null | head -n "$MAX_FILES" || echo "")
STATUS_LINE_COUNT=$(git status --short 2>/dev/null | wc -l | tr -d ' ' || echo "0")

# Last 3 commits
RECENT_COMMITS=$(git log --oneline -3 2>/dev/null || echo "(no commits yet)")

# Detect merge conflicts (files with UU / AA / DD markers)
CONFLICTS=$(git status --short 2>/dev/null | grep -E '^(UU|AA|DD|U |AU|UA) ' || true)

# ── write context file ────────────────────────────────────────────────────────

mkdir -p "$CONTEXT_DIR"

{
  printf '# Git Context\n\n'
  printf '_Updated: %s_\n\n' "$TIMESTAMP"
  printf '## Branch\n\n`%s`\n\n' "$BRANCH"

  printf '## Working Tree Status\n\n'
  if [[ -z "$STATUS_OUTPUT" ]]; then
    printf 'Clean — no uncommitted changes.\n\n'
  else
    printf '```\n%s\n```\n' "$STATUS_OUTPUT"
    if (( STATUS_LINE_COUNT > MAX_FILES )); then
      printf '\n_(output capped at %s lines; %s total changed files)_\n' "$MAX_FILES" "$STATUS_LINE_COUNT"
    fi
    printf '\n'
  fi

  printf '## Last 3 Commits\n\n```\n%s\n```\n\n' "$RECENT_COMMITS"

  if [[ -n "$CONFLICTS" ]]; then
    printf '## MERGE CONFLICTS DETECTED\n\n'
    printf 'The following files have conflict markers:\n\n```\n%s\n```\n\n' "$CONFLICTS"
  fi
} > "$OUTPUT_FILE"

exit 0
