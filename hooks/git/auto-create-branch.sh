#!/usr/bin/env bash
# Hook name:   auto-create-branch
# Event:       Stop
# Description: After each session, warns Claude when it has left uncommitted
#              changes (or made commits) directly on a protected branch.
#              Outputs context suggesting a feature branch name derived from
#              recent commit messages or changed file paths.
#
#              Triggers when ALL of the following are true:
#                1. Inside a git repository
#                2. Current branch is a protected branch (main/master/develop)
#                3. There are uncommitted changes OR commits made this session
#                   (detected via a session-scoped reflog check)
#
# Config (env vars):
#   CLAUDE_AUTO_BRANCH_SUGGEST=1       Enable suggestions. Default: 1.
#   CLAUDE_PROTECTED_BRANCHES          Space-separated protected branch names.
#                                      Default: "main master develop"
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
#               "command": "/path/to/hooks/git/auto-create-branch.sh"
                #             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-create-branch] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

if ! command -v git &>/dev/null; then
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_AUTO_BRANCH_SUGGEST:-1}" != "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  exit 0
fi

# ── git checks ────────────────────────────────────────────────────────────────

if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  exit 0
fi

PROTECTED_BRANCHES="${CLAUDE_PROTECTED_BRANCHES:-main master develop}"

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ -z "$CURRENT_BRANCH" ]]; then
  exit 0  # detached HEAD
fi

# Check if current branch is protected
IS_PROTECTED=0
for b in $PROTECTED_BRANCHES; do
  if [[ "$CURRENT_BRANCH" == "$b" ]]; then
    IS_PROTECTED=1
    break
  fi
done

if [[ "$IS_PROTECTED" == "0" ]]; then
  exit 0
fi

# ── detect work done on this branch ───────────────────────────────────────────

# Uncommitted changes (tracked or untracked-but-staged)
UNCOMMITTED=$(git status --porcelain 2>/dev/null | grep -v '^??' || true)

# Commits made in this session: check reflog for commits since the last
# "checkout" or "reset" entry (a proxy for "session start").
# We look at the last 20 reflog entries for this branch and count commits
# that appear after the most recent non-commit entry.
RECENT_COMMITS_ON_BRANCH=$(git log --oneline -10 2>/dev/null || true)

# Count commits ahead of upstream (or just commits if no upstream)
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")
COMMITS_AHEAD=0
if [[ -n "$UPSTREAM" ]]; then
  COMMITS_AHEAD=$(git rev-list --count "${UPSTREAM}..HEAD" 2>/dev/null || echo "0")
else
  # No upstream: count all commits as potential session work
  COMMITS_AHEAD=$(git rev-list --count HEAD 2>/dev/null || echo "0")
fi

# If neither uncommitted changes nor commits ahead of upstream — nothing to do
if [[ -z "$UNCOMMITTED" && "$COMMITS_AHEAD" == "0" ]]; then
  exit 0
fi

# ── generate a branch name suggestion ────────────────────────────────────────

# Derive a slug from the most recent commit message, or from the most
# frequently changed directory if there are only uncommitted changes.
SUGGESTED_SLUG=""

if [[ "$COMMITS_AHEAD" -gt 0 ]]; then
  # Use the first commit message ahead of upstream
  FIRST_COMMIT_MSG=$(git log --oneline -1 2>/dev/null | sed 's/^[a-f0-9]* //' || echo "")
  # Slugify: lowercase, replace non-alphanumerics with dashes, strip leading/trailing dashes
  SUGGESTED_SLUG=$(printf '%s' "$FIRST_COMMIT_MSG" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g' \
    | cut -c1-40)
fi

if [[ -z "$SUGGESTED_SLUG" && -n "$UNCOMMITTED" ]]; then
  # Use the most common changed directory
  TOP_DIR=$(git status --porcelain 2>/dev/null \
    | awk '{print $2}' \
    | xargs -I{} dirname {} 2>/dev/null \
    | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' \
    | tr '/' '-' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g' \
    | sed -E 's/^-+|-+$//g' \
    | cut -c1-30 || echo "")
  SUGGESTED_SLUG="${TOP_DIR:-changes}"
fi

BRANCH_SUGGESTION="feature/${SUGGESTED_SLUG:-work}"

# ── build context output ──────────────────────────────────────────────────────

STATUS_SUMMARY=""
if [[ -n "$UNCOMMITTED" ]]; then
  CHANGED_COUNT=$(printf '%s' "$UNCOMMITTED" | wc -l | tr -d ' ')
  STATUS_SUMMARY="${CHANGED_COUNT} uncommitted file(s)"
fi

AHEAD_SUMMARY=""
if [[ "$COMMITS_AHEAD" -gt 0 ]]; then
  AHEAD_SUMMARY="${COMMITS_AHEAD} commit(s) ahead of upstream"
fi

DETAIL="${STATUS_SUMMARY}${STATUS_SUMMARY:+${AHEAD_SUMMARY:+, }}${AHEAD_SUMMARY}"

CONTEXT="Branch safety notice: you are on protected branch '${CURRENT_BRANCH}' with ${DETAIL}.

Consider isolating this work on a feature branch:
  git checkout -b ${BRANCH_SUGGESTION}

If commits are already on ${CURRENT_BRANCH} and need moving:
  git checkout -b ${BRANCH_SUGGESTION}
  git checkout ${CURRENT_BRANCH}
  git reset --hard HEAD~${COMMITS_AHEAD}   # only if you want to clean ${CURRENT_BRANCH}

Set CLAUDE_AUTO_BRANCH_SUGGEST=0 to disable this notice."

jq -n --arg ctx "$CONTEXT" '{"context":$ctx}'
exit 0
