#!/usr/bin/env bash
# Hook name:   inject-file-history
# Event:       PreToolUse
# Matcher:     Read
# Description: When Claude reads a file, inject:
#              - Who last modified it and when (git blame last committer)
#              - How many commits touched it in the last 30 days
#              - Whether the file contains open TODO or FIXME markers
#
#              Only runs for files tracked in git. Silently approves for
#              untracked files, binaries, or directories.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Read",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/context/inject-file-history.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────

approve() { printf '{"decision":"approve"}\n'; exit 0; }

approve_with_context() {
  local ctx="$1"
  jq -n --arg c "$ctx" '{"decision":"approve","context":$c}'
  exit 0
}

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v git &>/dev/null; then
  approve
fi

if ! command -v jq &>/dev/null; then
  approve
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  approve
fi

TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r '.tool_input // {}')

FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '
  if type == "object" then (.file_path // "") else "" end
' 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]]; then
  approve
fi

# Resolve to absolute path
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="${PWD}/${FILE_PATH}"
fi

# Skip directories
if [[ -d "$FILE_PATH" ]]; then
  approve
fi

# Skip binary files (heuristic: check for null bytes in first 512 bytes)
if [[ -f "$FILE_PATH" ]] && LC_ALL=C python3 -c "import sys; data=open(sys.argv[1],'rb').read(512); sys.exit(0 if b'\x00' in data else 1)" "$FILE_PATH" 2>/dev/null; then
  approve
fi

# ── check file is tracked by git ─────────────────────────────────────────────

REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
  approve
fi

if ! git -C "$REPO_ROOT" ls-files --error-unmatch "$FILE_PATH" &>/dev/null 2>&1; then
  approve
fi

RELATIVE_PATH=$(git -C "$REPO_ROOT" ls-files --full-name "$FILE_PATH" 2>/dev/null || basename "$FILE_PATH")

# ── last modifier ─────────────────────────────────────────────────────────────

LAST_LOG=$(git -C "$REPO_ROOT" log \
  --follow \
  --format="%h %ad %an — %s" \
  --date=short \
  -1 \
  -- "$FILE_PATH" 2>/dev/null || echo "(no commit history)")

# ── commits in last 30 days ───────────────────────────────────────────────────

SINCE_DATE=$(date -u -v-30d +"%Y-%m-%d" 2>/dev/null || date -u -d "30 days ago" +"%Y-%m-%d" 2>/dev/null || echo "")

RECENT_COUNT=0
if [[ -n "$SINCE_DATE" ]]; then
  RECENT_COUNT=$(git -C "$REPO_ROOT" log \
    --follow \
    --oneline \
    --since="$SINCE_DATE" \
    -- "$FILE_PATH" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
fi

RECENT_COMMITS_LIST=$(git -C "$REPO_ROOT" log \
  --follow \
  --format="%h %ad %an — %s" \
  --date=short \
  -5 \
  -- "$FILE_PATH" 2>/dev/null || echo "(none)")

# ── TODO / FIXME scan ─────────────────────────────────────────────────────────

TODO_COUNT=0
TODO_LINES=""
if [[ -f "$FILE_PATH" ]]; then
  TODO_COUNT=$(grep -cEi '(TODO|FIXME|HACK|XXX):?' "$FILE_PATH" 2>/dev/null || echo "0")
  if (( TODO_COUNT > 0 )); then
    TODO_LINES=$(grep -nEi '(TODO|FIXME|HACK|XXX):?' "$FILE_PATH" 2>/dev/null | head -10 || true)
  fi
fi

# ── total commit count ────────────────────────────────────────────────────────

TOTAL_COMMITS=$(git -C "$REPO_ROOT" log \
  --follow \
  --oneline \
  -- "$FILE_PATH" 2>/dev/null | wc -l | tr -d ' ' || echo "0")

# ── build context ─────────────────────────────────────────────────────────────

CONTEXT="File history for \`${RELATIVE_PATH}\`:\n\n"
CONTEXT+="**Last modified:** ${LAST_LOG}\n"
CONTEXT+="**Total commits:** ${TOTAL_COMMITS}\n"
CONTEXT+="**Commits in last 30 days:** ${RECENT_COUNT}\n\n"
CONTEXT+="**Recent commits (last 5):**\n\`\`\`\n${RECENT_COMMITS_LIST}\n\`\`\`\n\n"

if (( TODO_COUNT > 0 )); then
  CONTEXT+="**Open TODO/FIXME markers (${TODO_COUNT} total, showing first 10):**\n\`\`\`\n${TODO_LINES}\n\`\`\`\n"
else
  CONTEXT+="**TODO/FIXME markers:** none found.\n"
fi

approve_with_context "$CONTEXT"
