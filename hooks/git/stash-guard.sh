#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   stash-guard
# Event:       PreToolUse (matcher: "Bash")
# Description: Warns (or blocks) when Claude is about to run commands that
#              could silently discard or conflict with uncommitted changes.
#
#              Monitored commands:
#                git checkout <branch>    — switching branches with dirty tree
#                git switch <branch>      — same
#                git stash pop            — can create merge conflicts
#                git stash apply          — same
#                git pull --rebase        — rebasing onto a dirty tree
#                git pull                 — merge into dirty tree
#                git reset --hard         — explicitly destructive
#                git merge <branch>       — merging into dirty tree
#
#              Default behaviour: approve with a context warning (exit 0).
#              With CLAUDE_STASH_GUARD_BLOCK=1: block via permissionDecision=deny.
#
# Config (env vars):
#   CLAUDE_STASH_GUARD_BLOCK=1   Upgrade from warn to hard block.
#   CLAUDE_STASH_GUARD_SKIP=1    Disable the guard entirely.
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
#               "command": "/path/to/hooks/git/stash-guard.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[stash-guard] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

if ! command -v git &>/dev/null; then
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_STASH_GUARD_SKIP:-0}" == "1" ]]; then
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

# ── check if command is one we care about ────────────────────────────────────

RISKY_COMMAND=""
RISK_DETAIL=""

# git checkout / git switch — branch switching
if printf '%s' "$COMMAND" | grep -qE '^\s*git\s+(checkout|switch)\s+[^-]'; then
  RISKY_COMMAND="branch switch"
  RISK_DETAIL="Switching branches with uncommitted changes can cause git to refuse the operation or silently carry changes into the new branch."
fi

# git stash pop / apply
if [[ -z "$RISKY_COMMAND" ]] && printf '%s' "$COMMAND" | grep -qE '^\s*git\s+stash\s+(pop|apply)\b'; then
  RISKY_COMMAND="stash pop/apply"
  RISK_DETAIL="Popping or applying a stash onto a dirty working tree can produce unresolvable conflicts."
fi

# git pull --rebase
if [[ -z "$RISKY_COMMAND" ]] && printf '%s' "$COMMAND" | grep -qE '^\s*git\s+pull\s+.*--rebase'; then
  RISKY_COMMAND="pull --rebase"
  RISK_DETAIL="Rebasing onto a dirty tree may abort mid-way or produce confusing conflict state."
fi

# git pull (plain)
if [[ -z "$RISKY_COMMAND" ]] && printf '%s' "$COMMAND" | grep -qE '^\s*git\s+pull(\s|$)'; then
  RISKY_COMMAND="pull"
  RISK_DETAIL="Merging remote changes into a dirty working tree can complicate conflict resolution."
fi

# git reset --hard
if [[ -z "$RISKY_COMMAND" ]] && printf '%s' "$COMMAND" | grep -qE '^\s*git\s+reset\s+.*--hard'; then
  RISKY_COMMAND="reset --hard"
  RISK_DETAIL="'git reset --hard' permanently discards uncommitted changes — they cannot be recovered."
fi

# git merge
if [[ -z "$RISKY_COMMAND" ]] && printf '%s' "$COMMAND" | grep -qE '^\s*git\s+merge\s+[^-]'; then
  RISKY_COMMAND="merge"
  RISK_DETAIL="Merging into a dirty working tree may produce conflicts on top of existing local edits."
fi

# Not a monitored command
if [[ -z "$RISKY_COMMAND" ]]; then
  exit 0
fi

# ── check for uncommitted changes ────────────────────────────────────────────

# Not in a git repo — nothing to warn about
if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  exit 0
fi

STATUS=$(git status --porcelain 2>/dev/null || true)
if [[ -z "$STATUS" ]]; then
  exit 0  # clean tree — no warning needed
fi

# ── build warning / block response ───────────────────────────────────────────

# Limit status output to 20 lines to keep context readable
STATUS_EXCERPT=$(printf '%s' "$STATUS" | head -20)
TOTAL_LINES=$(printf '%s' "$STATUS" | wc -l | tr -d ' ')
TRUNCATED_NOTE=""
if (( TOTAL_LINES > 20 )); then
  TRUNCATED_NOTE="
... (${TOTAL_LINES} total changed files, showing first 20)"
fi

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached HEAD")

CONTEXT="Warning: stash-guard detected uncommitted changes before a risky git operation.

Operation: ${RISKY_COMMAND}
Branch: ${CURRENT_BRANCH}

${RISK_DETAIL}

Uncommitted changes:
${STATUS_EXCERPT}${TRUNCATED_NOTE}

Recommended: stash your changes first:
  git stash push -m \"wip: before ${RISKY_COMMAND}\"
  # ... run the command ...
  git stash pop

Set CLAUDE_STASH_GUARD_BLOCK=1 to block these operations outright.
Set CLAUDE_STASH_GUARD_SKIP=1 to silence this warning."

if [[ "${CLAUDE_STASH_GUARD_BLOCK:-0}" == "1" ]]; then
  BLOCK_REASON="Blocked: ${RISKY_COMMAND} attempted with uncommitted changes. ${RISK_DETAIL} Stash your changes first, or set CLAUDE_STASH_GUARD_SKIP=1 to bypass."
  jq -n --arg reason "$BLOCK_REASON" '
    {
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }
    '
  exit 0
fi

jq -n --arg ctx "$CONTEXT" '{"decision":"approve","context":$ctx}'
exit 0
