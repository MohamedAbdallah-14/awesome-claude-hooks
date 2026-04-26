#!/usr/bin/env bash
# Hook name:   auto-changelog
# Event:       Stop
# Description: Appends a dated entry to CHANGELOG.md when Claude finishes a
#              session that produced file changes. The entry summary is taken
#              from the last user message in the transcript (what Claude was
#              asked to do).
#
#              Entry format:
#                ## YYYY-MM-DD
#                - {summary_from_transcript}
#
#              If CHANGELOG.md does not exist it is created with a header.
#              Skips silently if no file changes were made during the session.
#
# Config (env vars):
#   CLAUDE_AUTO_CHANGELOG=0    Set to 1 to enable (opt-in, default OFF).
#   CLAUDE_CHANGELOG_FILE      Override path to changelog file.
#                              Default: {repo_root}/CHANGELOG.md
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
#               "command": "/path/to/hooks/automation/auto-changelog.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── opt-in gate ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_AUTO_CHANGELOG:-0}" != "1" ]]; then
  exit 0
fi

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-changelog] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

if ! command -v git &>/dev/null; then
  echo "[auto-changelog] WARNING: git not found — skipping changelog" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')

# ── git repo check ────────────────────────────────────────────────────────────

if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  echo "[auto-changelog] Not inside a git repo — skipping" >&2
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

# ── check if any files were changed ──────────────────────────────────────────

CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null || true)
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)
UNCOMMITTED=$(git status --porcelain 2>/dev/null | grep -v '^??' || true)

if [[ -z "$CHANGED_FILES" && -z "$STAGED_FILES" && -z "$UNCOMMITTED" ]]; then
  echo "[auto-changelog] No file changes detected — skipping changelog entry"
  exit 0
fi

# ── resolve changelog path ────────────────────────────────────────────────────

CHANGELOG_FILE="${CLAUDE_CHANGELOG_FILE:-$REPO_ROOT/CHANGELOG.md}"

# ── extract summary from transcript ──────────────────────────────────────────

ISO_DATE=$(date -u +"%Y-%m-%d")
SUMMARY="session $ISO_DATE"

if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  # find the last user message text
  LAST_USER_TEXT=$(jq -r 'select(.role == "user") | .content' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || true)

  if [[ -n "$LAST_USER_TEXT" && "$LAST_USER_TEXT" != "null" ]]; then
    # content may be a JSON array of blocks
    if printf '%s' "$LAST_USER_TEXT" | jq -e 'type == "array"' &>/dev/null 2>&1; then
      SUMMARY=$(printf '%s' "$LAST_USER_TEXT" | jq -r '[.[] | select(.type == "text") | .text] | first // ""' 2>/dev/null || true)
    else
      SUMMARY="$LAST_USER_TEXT"
    fi

    # clean up: first line, strip markdown, truncate
    if [[ -n "$SUMMARY" && "$SUMMARY" != "null" ]]; then
      SUMMARY=$(printf '%s' "$SUMMARY" | head -1 | sed 's/^[#* ]*//;s/[`*_]//g')
      SUMMARY="${SUMMARY:0:120}"
    else
      SUMMARY="session $ISO_DATE"
    fi
  fi
fi

# ── create CHANGELOG.md if missing ────────────────────────────────────────────

if [[ ! -f "$CHANGELOG_FILE" ]]; then
  {
    printf '# Changelog\n\n'
    printf 'All notable changes to this project are documented here.\n\n'
  } > "$CHANGELOG_FILE"
  echo "[auto-changelog] Created $CHANGELOG_FILE"
fi

# ── check if today's heading already exists ───────────────────────────────────

if grep -qF "## $ISO_DATE" "$CHANGELOG_FILE" 2>/dev/null; then
  # append a bullet under the existing date section
  # use a temp file approach to insert after the heading line
  TEMP_FILE=$(mktemp)
  awk -v date="## $ISO_DATE" -v entry="- $SUMMARY" '
    $0 == date { print; print entry; next }
    { print }
  ' "$CHANGELOG_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CHANGELOG_FILE"
  echo "[auto-changelog] Appended entry under existing $ISO_DATE section"
else
  # prepend a new date section after the first line (the # Changelog header)
  TEMP_FILE=$(mktemp)
  awk -v date="## $ISO_DATE" -v entry="- $SUMMARY" '
    NR == 1 { print; print ""; print date; print entry; print ""; next }
    { print }
  ' "$CHANGELOG_FILE" > "$TEMP_FILE"
  mv "$TEMP_FILE" "$CHANGELOG_FILE"
  echo "[auto-changelog] Added new $ISO_DATE section to $CHANGELOG_FILE"
fi

echo "[auto-changelog] Entry: $SUMMARY"

exit 0
