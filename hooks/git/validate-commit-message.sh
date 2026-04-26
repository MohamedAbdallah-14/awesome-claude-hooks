#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   validate-commit-message
# Event:       PreToolUse (matcher: "Bash")
# Description: Validates git commit messages against Conventional Commits format.
#
#              Expected format: type(scope): description
#              Valid types: feat fix docs style refactor test chore perf ci build revert
#
#              Examples:
#                feat(auth): add OAuth2 login flow
#                fix: correct null pointer in payment handler
#                chore(deps): bump lodash to 4.17.21
#
#              Skips validation for:
#                git commit --amend --no-edit
#                git commit --no-edit
#
# Config (env vars):
#   CLAUDE_COMMIT_REGEX           Override the validation regex (POSIX ERE).
#                                 Default enforces conventional commits.
#   CLAUDE_SKIP_COMMIT_VALIDATION=1   Disable all validation.
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
#               "command": "/path/to/hooks/git/validate-commit-message.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[validate-commit-message] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_SKIP_COMMIT_VALIDATION:-0}" == "1" ]]; then
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

# ── filter: only act on git commit commands ───────────────────────────────────

# Must look like a git commit invocation
if ! printf '%s' "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
  exit 0
fi

# --no-edit: amending without touching the message — skip
if printf '%s' "$COMMAND" | grep -qE -- '--no-edit'; then
  exit 0
fi

# --allow-empty or -C (reuse message): skip
if printf '%s' "$COMMAND" | grep -qE -- '(-C\s|--reuse-message)'; then
  exit 0
fi

# ── extract the commit message from -m "..." ──────────────────────────────────

# Support both: -m "msg" and -m 'msg'
# Also handles: git commit -m "$(cat <<'EOF' ... EOF)"  — we grab what jq gives us
# The raw command string is what we validate.

# Strip everything before -m / --message, then capture the quoted value.
# We use a two-pass approach: first strip flags, then grab the message.

COMMIT_MSG=""

# Try -m "..." or -m '...'  (single-line extraction)
if printf '%s' "$COMMAND" | grep -qE -- '-m[[:space:]]'; then
  # Extract text after -m, handling both quote styles
  COMMIT_MSG=$(printf '%s' "$COMMAND" \
    | sed -E "s/.*-m[[:space:]]+['\"]?//" \
    | sed -E "s/['\"][[:space:]]*(-[a-zA-Z].*)?$//" \
    | head -1)
fi

# If no -m flag was found the commit must use an editor — we can't validate that
# at PreToolUse time, so let it through.
if [[ -z "$COMMIT_MSG" ]]; then
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

# Conventional commits: type(optional-scope): description
# type must be one of the known types; scope is optional; description is required.
DEFAULT_REGEX='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\([a-zA-Z0-9_/.-]+\))?(!)?: .{1,}'
COMMIT_REGEX="${CLAUDE_COMMIT_REGEX:-$DEFAULT_REGEX}"

# ── validate ──────────────────────────────────────────────────────────────────

if printf '%s' "$COMMIT_MSG" | grep -qE "$COMMIT_REGEX"; then
  exit 0
fi

# ── build a helpful block message ─────────────────────────────────────────────

VALID_TYPES="feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert"

REASON="Commit message does not follow Conventional Commits format.

Message: \"${COMMIT_MSG}\"

Required format: type(scope): description
  - type must be one of: ${VALID_TYPES}
  - scope is optional (parentheses)
  - description must follow the colon and a space

Examples of valid messages:
  feat(auth): add OAuth2 login flow
  fix: correct null pointer in payment handler
  chore(deps): bump lodash to 4.17.21
  docs: update README with setup instructions

Set CLAUDE_SKIP_COMMIT_VALIDATION=1 to bypass, or set CLAUDE_COMMIT_REGEX to use a custom pattern."

jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}'
exit 2
