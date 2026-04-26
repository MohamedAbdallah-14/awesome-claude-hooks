#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   protect-main-branch
# Event:       PreToolUse (matcher: "Bash")
# Description: Blocks destructive git operations targeting protected branches.
#
#              Catches:
#                git push --force / -f  →  main, master, or any protected branch
#                git push -f            →  same
#                git reset --hard       →  when current branch is protected
#                git branch -D          →  targeting a protected branch
#                git checkout -B        →  recreating a protected branch
#
# Config (env vars):
#   CLAUDE_PROTECTED_BRANCHES   Space-separated list of protected branch names.
#                               Default: "main master develop"
#   CLAUDE_ALLOW_FORCE_PUSH=1   Disable all protection (escape hatch).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/git/protect-main-branch.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[protect-main-branch] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_ALLOW_FORCE_PUSH:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

PROTECTED_BRANCHES="${CLAUDE_PROTECTED_BRANCHES:-main master develop}"

# ── helper: check if a branch name appears in the protected list ──────────────

is_protected() {
  local branch="$1"
  local b
  for b in $PROTECTED_BRANCHES; do
    if [[ "$branch" == "$b" ]]; then
      return 0
    fi
  done
  return 1
}

# ── helper: get current branch (may not be in a git repo) ────────────────────

current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}

# ── pattern matching ──────────────────────────────────────────────────────────

BLOCK_REASON=""

# 1. git push --force / -f
#    Matches: git push --force origin main
#             git push -f origin master
#             git push --force-with-lease origin main  (still risky — block it)
if printf '%s' "$COMMAND" | grep -qE '^\s*git\s+push\s+.*(-f\b|--force\b|--force-with-lease\b)'; then
  # Extract the branch token — the last word on the line is usually the refspec/branch
  PUSH_BRANCH=$(printf '%s' "$COMMAND" | grep -oE '[a-zA-Z0-9_/.-]+$' | tail -1)
  # Also check if any protected branch name appears anywhere in the command
  FOUND_PROTECTED=""
  for b in $PROTECTED_BRANCHES; do
    if printf '%s' "$COMMAND" | grep -qE "(^|\s|:)${b}(\s|$|:)"; then
      FOUND_PROTECTED="$b"
      break
    fi
  done
  # If an explicit protected branch is named, or the last token is one, block
  if [[ -n "$FOUND_PROTECTED" ]] || is_protected "$PUSH_BRANCH" 2>/dev/null; then
    TARGET="${FOUND_PROTECTED:-$PUSH_BRANCH}"
    BLOCK_REASON="Force-pushing to '${TARGET}' is blocked. Protected branches: ${PROTECTED_BRANCHES}. Set CLAUDE_ALLOW_FORCE_PUSH=1 to override."
  fi
fi

# 2. git reset --hard while on a protected branch
if [[ -z "$BLOCK_REASON" ]]; then
  if printf '%s' "$COMMAND" | grep -qE '^\s*git\s+reset\s+.*--hard'; then
    CURRENT=$(current_branch)
    if [[ -n "$CURRENT" ]] && is_protected "$CURRENT"; then
      BLOCK_REASON="'git reset --hard' on protected branch '${CURRENT}' is blocked. Switch to a feature branch first. Set CLAUDE_ALLOW_FORCE_PUSH=1 to override."
    fi
  fi
fi

# 3. git branch -D <protected-branch>
if [[ -z "$BLOCK_REASON" ]]; then
  if printf '%s' "$COMMAND" | grep -qE '^\s*git\s+branch\s+.*-D'; then
    # Extract branch name(s) after -D
    DELETE_BRANCH=$(printf '%s' "$COMMAND" | sed -E 's/.*-D[[:space:]]+//' | awk '{print $1}')
    if [[ -n "$DELETE_BRANCH" ]] && is_protected "$DELETE_BRANCH"; then
      BLOCK_REASON="Deleting protected branch '${DELETE_BRANCH}' is blocked. Protected branches: ${PROTECTED_BRANCHES}. Set CLAUDE_ALLOW_FORCE_PUSH=1 to override."
    fi
  fi
fi

# 4. git checkout -B <protected-branch>  (force-recreate)
if [[ -z "$BLOCK_REASON" ]]; then
  if printf '%s' "$COMMAND" | grep -qE '^\s*git\s+checkout\s+.*-B'; then
    RECREATE_BRANCH=$(printf '%s' "$COMMAND" | sed -E 's/.*-B[[:space:]]+//' | awk '{print $1}')
    if [[ -n "$RECREATE_BRANCH" ]] && is_protected "$RECREATE_BRANCH"; then
      BLOCK_REASON="Force-recreating protected branch '${RECREATE_BRANCH}' via 'checkout -B' is blocked. Protected branches: ${PROTECTED_BRANCHES}. Set CLAUDE_ALLOW_FORCE_PUSH=1 to override."
    fi
  fi
fi

# ── decision ──────────────────────────────────────────────────────────────────

if [[ -n "$BLOCK_REASON" ]]; then
  jq -n --arg reason "$BLOCK_REASON" '{"decision":"block","reason":$reason}'
  exit 2
fi

exit 0
