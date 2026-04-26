#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   conflict-detector
# Event:       PreToolUse (matcher: "Edit|Write|MultiEdit")
# Description: Before Claude edits a file, checks it for unresolved merge
#              conflict markers. Warns Claude so it doesn't blindly overwrite
#              a file that still needs manual conflict resolution.
#
#              Detects the standard git conflict marker set:
#                <<<<<<< (ours / HEAD)
#                =======  (separator)
#                >>>>>>> (theirs / incoming)
#
#              Also detects diff3-style base marker:
#                ||||||| (base section)
#
# Config (env vars):
#   CLAUDE_BLOCK_CONFLICT_EDITS=1   Upgrade from warn to hard block.
#   CLAUDE_CONFLICT_SKIP=1          Disable the detector entirely.
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
#               "command": "/path/to/hooks/git/conflict-detector.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[conflict-detector] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_CONFLICT_SKIP:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

# Extract file path depending on the tool
FILE_PATH=""
case "$TOOL_NAME" in
  Write|Edit)
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
    ;;
  MultiEdit)
    # MultiEdit has an array of edits; all target the same file_path at top-level
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
    ;;
  *)
    exit 0
    ;;
esac

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── file existence check ──────────────────────────────────────────────────────

# For Write, the file might not exist yet — no conflict markers possible
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── conflict marker scan ──────────────────────────────────────────────────────

# Count lines that start with the conflict markers
# We use grep -c (count) so we don't output matching content to stdout.
OURS_COUNT=0
SEP_COUNT=0
THEIRS_COUNT=0

OURS_COUNT=$(grep -c '^<<<<<<< ' "$FILE_PATH" 2>/dev/null || true)
SEP_COUNT=$(grep -c '^=======$' "$FILE_PATH" 2>/dev/null || true)
THEIRS_COUNT=$(grep -c '^>>>>>>> ' "$FILE_PATH" 2>/dev/null || true)

# diff3 base section (optional — extra signal)
BASE_COUNT=$(grep -c '^||||||| ' "$FILE_PATH" 2>/dev/null || true)

HAS_CONFLICT=0
if (( OURS_COUNT > 0 || SEP_COUNT > 0 || THEIRS_COUNT > 0 )); then
  HAS_CONFLICT=1
fi

if [[ "$HAS_CONFLICT" == "0" ]]; then
  exit 0
fi

# ── extract a snippet of the first conflict for context ──────────────────────

FIRST_CONFLICT_LINE=$(grep -n '^<<<<<<< ' "$FILE_PATH" 2>/dev/null | head -1 | cut -d: -f1 || echo "?")

SNIPPET_START=$(( FIRST_CONFLICT_LINE > 3 ? FIRST_CONFLICT_LINE - 3 : 1 ))
SNIPPET=$(sed -n "${SNIPPET_START},$((FIRST_CONFLICT_LINE + 15))p" "$FILE_PATH" 2>/dev/null || true)

# ── decision ──────────────────────────────────────────────────────────────────

WARN_MSG="Warning: '${FILE_PATH}' contains unresolved merge conflict markers.

Marker counts — ours (<<<<<<): ${OURS_COUNT}  separator (=======): ${SEP_COUNT}  theirs (>>>>>>>): ${THEIRS_COUNT}${BASE_COUNT:+  diff3-base (|||||||): ${BASE_COUNT}}
First conflict near line ${FIRST_CONFLICT_LINE}.

You must resolve the conflicts before editing this file:
  1. Open the file and choose between the conflicting sections.
  2. Remove all <<<<<<<, =======, and >>>>>>> markers.
  3. Stage the resolved file: git add ${FILE_PATH}
  4. Then edit as needed.

Set CLAUDE_BLOCK_CONFLICT_EDITS=1 to block edits to conflicted files outright.
Set CLAUDE_CONFLICT_SKIP=1 to silence this warning."

if [[ "${CLAUDE_BLOCK_CONFLICT_EDITS:-0}" == "1" ]]; then
  BLOCK_REASON="Blocked: '${FILE_PATH}' has ${OURS_COUNT} unresolved merge conflict(s). Resolve the conflict markers before editing. Set CLAUDE_CONFLICT_SKIP=1 to bypass."
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

jq -n --arg ctx "$WARN_MSG" '{"decision":"approve","context":$ctx}'
exit 0
