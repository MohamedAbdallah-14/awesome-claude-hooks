#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   inject-recent-commits
# Event:       PreToolUse
# Matcher:     Edit|Write|MultiEdit
# Description: Before Claude edits a file, injects that file's recent git log
#              as context so Claude knows what changed and why before modifying.
#              Outputs JSON with decision + context fields.
#              Silently approves if file is untracked or git is unavailable.
#
# Config (env vars):
#   CLAUDE_GIT_LOG_COUNT   Number of log entries to show per file. Default: 5.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Edit|Write|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/context/inject-recent-commits.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

approve() { printf '{"decision":"approve"}\n'; exit 0; }

if ! command -v git &>/dev/null; then
  approve
fi

if ! command -v jq &>/dev/null; then
  approve
fi

# ── config ────────────────────────────────────────────────────────────────────

LOG_COUNT="${CLAUDE_GIT_LOG_COUNT:-5}"

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  approve
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r '.tool_input // {}')

# ── resolve file path from tool input ────────────────────────────────────────
# Edit/MultiEdit use "file_path"; Write uses "file_path" as well.

FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '
  if type == "object" then
    (
      .file_path //
      (.edits[0].file_path? // "") //
      ""
    )
  else ""
  end
' 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]]; then
  approve
fi

# Resolve to absolute path; the hook runs in the session working directory
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="${PWD}/${FILE_PATH}"
fi

# ── check repo and tracking ───────────────────────────────────────────────────

REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
  approve
fi

# Check the file is tracked (git ls-files exits 0 and prints the path if tracked)
TRACKED=$(git -C "$REPO_ROOT" ls-files --error-unmatch "$FILE_PATH" 2>/dev/null || true)
if [[ -z "$TRACKED" ]]; then
  # Untracked file — no history to show
  approve
fi

# ── fetch git log for file ────────────────────────────────────────────────────

LOG_OUTPUT=$(git -C "$REPO_ROOT" log \
  --oneline \
  --follow \
  --format="%h %ad %an — %s" \
  --date=short \
  -"$LOG_COUNT" \
  -- "$FILE_PATH" 2>/dev/null || true)

if [[ -z "$LOG_OUTPUT" ]]; then
  approve
fi

_relpath() { python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2" 2>/dev/null || echo "$1"; }
RELATIVE_PATH=$(_relpath "$FILE_PATH" "$REPO_ROOT")

CONTEXT="Recent changes to \`${RELATIVE_PATH}\` (last ${LOG_COUNT} commits):\n\`\`\`\n${LOG_OUTPUT}\n\`\`\`"

# ── emit JSON response ────────────────────────────────────────────────────────

jq -n \
  --arg context "$CONTEXT" \
  '{"decision":"approve","context":$context}'

exit 0
