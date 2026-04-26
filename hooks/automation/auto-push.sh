#!/usr/bin/env bash
# Hook name:   auto-push
# Event:       Stop
# Description: After a Claude session ends, pushes the current branch to its
#              upstream remote — but only if the last commit was made by Claude
#              (identified by a "claude:" message prefix). This makes auto-push
#              safe to pair with auto-git-commit without accidentally pushing
#              manual commits.
#
#              Safety guards:
#                - Off by default (must set CLAUDE_AUTO_PUSH=1)
#                - Never pushes to main/master (configurable)
#                - Only pushes if HEAD commit message starts with "claude:"
#                - Skips if no upstream is configured
#                - Never force-pushes
#
# Config (env vars):
#   CLAUDE_AUTO_PUSH=0               Set to 1 to enable (opt-in, default OFF).
#   CLAUDE_AUTO_PUSH_PROTECTED       Space-separated branches to never push.
#                                    Default: "main master"
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
#               "command": "/path/to/hooks/automation/auto-push.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── opt-in gate ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_AUTO_PUSH:-0}" != "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-push] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

if ! command -v git &>/dev/null; then
  echo "[auto-push] WARNING: git not found — skipping push" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
# session_id available if needed for logging
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')

# ── git repo check ────────────────────────────────────────────────────────────

if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  echo "[auto-push] Not inside a git repo — skipping" >&2
  exit 0
fi

# ── branch protection ─────────────────────────────────────────────────────────

PROTECTED_BRANCHES="${CLAUDE_AUTO_PUSH_PROTECTED:-main master}"
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "HEAD")

for PROTECTED in $PROTECTED_BRANCHES; do
  if [[ "$CURRENT_BRANCH" == "$PROTECTED" ]]; then
    echo "[auto-push] Skipping push — on protected branch: $CURRENT_BRANCH" >&2
    exit 0
  fi
done

# ── verify last commit was made by Claude ─────────────────────────────────────

LAST_MSG=$(git log -1 --format="%s" 2>/dev/null || true)

if [[ -z "$LAST_MSG" ]]; then
  echo "[auto-push] No commits found — skipping push"
  exit 0
fi

if [[ "$LAST_MSG" != claude:* ]]; then
  echo "[auto-push] Last commit was not made by Claude (\"$LAST_MSG\") — skipping push"
  exit 0
fi

# ── check upstream exists ─────────────────────────────────────────────────────

UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>/dev/null || true)

if [[ -z "$UPSTREAM" ]]; then
  # no upstream configured — try to set one on origin
  if git remote get-url origin &>/dev/null 2>&1; then
    echo "[auto-push] No upstream set — pushing with -u origin $CURRENT_BRANCH"
    PUSH_ARGS=("-u" "origin" "$CURRENT_BRANCH")
  else
    echo "[auto-push] No upstream and no 'origin' remote — skipping push" >&2
    exit 0
  fi
else
  PUSH_ARGS=()
fi

# ── push ──────────────────────────────────────────────────────────────────────

echo "[auto-push] Pushing branch $CURRENT_BRANCH to remote"

PUSH_EXIT=0
git push "${PUSH_ARGS[@]}" 2>&1 || PUSH_EXIT=$?

if [[ $PUSH_EXIT -eq 0 ]]; then
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "remote")
  echo "[auto-push] Pushed $CURRENT_BRANCH successfully"
else
  echo "[auto-push] WARNING: git push failed (exit $PUSH_EXIT)" >&2
fi

exit 0
