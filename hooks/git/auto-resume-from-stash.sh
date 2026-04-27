#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   auto-resume-from-stash
# Event:       SessionStart (matcher: "resume")
# Description: Smart `git stash pop`. When a Claude session is resumed,
#              look for a stash whose message starts with the magic
#              prefix `claude-auto:` AND was created on the current
#              branch, and pop it. Idempotent — only ever pops one
#              stash, and only one matching the current branch.
#
#              Pairs with a SessionEnd-side hook (or your own habit) that
#              creates such a stash via:
#                git stash push -u -m "claude-auto: $(git rev-parse --abbrev-ref HEAD)"
#
#              On its own, this hook is safe: if there is no matching
#              stash, it does nothing. It never touches stashes whose
#              message lacks the `claude-auto:` prefix, so manually
#              created stashes are left alone.
#
#              Surfaces a one-line `additionalContext` so Claude knows
#              the stash was popped and can mention it to the user.
#
# Config (env vars):
#   CLAUDE_AUTO_STASH_PREFIX     Prefix used to identify Claude-managed
#                                stashes. Default: "claude-auto:"
#   CLAUDE_AUTO_RESUME_STASH_OFF=1   Disable this hook (bypass).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "SessionStart": [
#         {
#           "matcher": "resume",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/git/auto-resume-from-stash.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "[auto-resume-from-stash] WARNING: jq not found — install it (brew install jq / apt-get install jq)" >&2
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  # No git — nothing to do.
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_AUTO_RESUME_STASH_OFF:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

# Only run on resume. Some installations omit the matcher and let the
# hook decide; double-check `source` to be safe.
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // ""')
if [[ -n "$SOURCE" && "$SOURCE" != "resume" ]]; then
  exit 0
fi

# Use the session's cwd if provided.
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
if [[ -n "$CWD" && -d "$CWD" ]]; then
  cd "$CWD" || exit 0
fi

# Must be inside a git repo.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

PREFIX="${CLAUDE_AUTO_STASH_PREFIX:-claude-auto:}"

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ -z "$CURRENT_BRANCH" ]]; then
  # Detached HEAD — refuse to guess.
  exit 0
fi

# ── find a matching stash ─────────────────────────────────────────────────────
# Iterate stashes; pick the first one whose subject starts with $PREFIX
# and whose message contains the current branch name. Stop at the first
# match — popping happens once per session.

STASH_REF=""
STASH_SUBJECT=""

# `git stash list` output looks like:
#   stash@{0}: On feature/foo: claude-auto: feature/foo
while IFS= read -r line; do
  ref="${line%%:*}"                      # stash@{0}
  rest="${line#*: }"                     # "On feature/foo: claude-auto: feature/foo"
  subject="${rest#*: }"                  # "claude-auto: feature/foo"
  case "$subject" in
    "${PREFIX}"*)
      # The stash message itself must reference the current branch.
      # We deliberately ignore the "On <branch>:" prefix git auto-adds —
      # that just records where the stash was created, not where it
      # belongs. Checking the prefix would falsely match every
      # claude-auto stash created on `main` regardless of target.
      branch_in_subject="${subject#"${PREFIX}"}"
      branch_in_subject="${branch_in_subject## }"   # left-trim spaces
      branch_in_subject="${branch_in_subject%% *}"  # first whitespace-delimited token
      if [[ "$branch_in_subject" == "$CURRENT_BRANCH" ]]; then
        STASH_REF="$ref"
        STASH_SUBJECT="$subject"
        break
      fi
      ;;
  esac
done < <(git stash list 2>/dev/null || true)

if [[ -z "$STASH_REF" ]]; then
  exit 0
fi

# ── safety: refuse to pop if working tree has uncommitted changes ─────────────
# Popping over a dirty tree can produce confusing conflicts. Surface the
# situation to Claude instead.

# `git status --porcelain` covers tracked changes, staged changes, AND
# untracked files — popping over any of these can cause a mess.
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  jq -n \
    --arg ref "$STASH_REF" \
    --arg subj "$STASH_SUBJECT" \
    --arg branch "$CURRENT_BRANCH" \
    '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "auto-resume-from-stash: found a matching stash (\($ref): \($subj)) on branch \($branch) but the working tree is dirty. Skipping pop. Resolve or commit current changes, then run: git stash pop \($ref)"
      }
    }'
  exit 0
fi

# ── pop ───────────────────────────────────────────────────────────────────────

if POP_OUT=$(git stash pop "$STASH_REF" 2>&1); then
  jq -n \
    --arg ref "$STASH_REF" \
    --arg subj "$STASH_SUBJECT" \
    --arg branch "$CURRENT_BRANCH" \
    '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "auto-resume-from-stash: popped \($ref) (\($subj)) onto branch \($branch). Inspect the working tree before continuing."
      }
    }'
  exit 0
else
  # Pop failed (likely a conflict). Don't error out — surface the message.
  jq -n \
    --arg ref "$STASH_REF" \
    --arg out "$POP_OUT" \
    '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: "auto-resume-from-stash: attempted to pop \($ref) but it conflicted. Resolve conflicts manually. git output: \($out)"
      }
    }'
  exit 0
fi
