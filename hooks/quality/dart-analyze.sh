#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   dart-analyze
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .dart file, runs static analysis and
#              reports errors and warnings separately so Claude can prioritize
#              fixes. Uses `flutter analyze` when available (or forced), falls
#              back to `dart analyze`.
#
#              Matches: .dart
#
# Config (env vars):
#   CLAUDE_DART_USE_FLUTTER=1   Force `flutter analyze` even when `dart` is
#                               also available. Default: auto-detect.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Write|Edit|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/quality/dart-analyze.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[dart-analyze] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── extension filter ──────────────────────────────────────────────────────────

case "$FILE_PATH" in
  *.dart) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── tool selection ────────────────────────────────────────────────────────────

ANALYZE_CMD=""

if [[ "${CLAUDE_DART_USE_FLUTTER:-0}" == "1" ]]; then
  if ! command -v flutter &>/dev/null; then
    echo "[dart-analyze] WARNING: CLAUDE_DART_USE_FLUTTER=1 but flutter not found in PATH — skipping" >&2
    exit 0
  fi
  ANALYZE_CMD="flutter analyze"
elif command -v flutter &>/dev/null; then
  # Prefer flutter analyze in Flutter projects (detects pubspec.yaml with flutter dep)
  PROJECT_ROOT=$(dirname "$FILE_PATH")
  while [[ "$PROJECT_ROOT" != "/" ]]; do
    if [[ -f "$PROJECT_ROOT/pubspec.yaml" ]]; then
      if grep -q "flutter:" "$PROJECT_ROOT/pubspec.yaml" 2>/dev/null; then
        ANALYZE_CMD="flutter analyze"
      fi
      break
    fi
    PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
  done
  if [[ -z "$ANALYZE_CMD" ]] && command -v dart &>/dev/null; then
    ANALYZE_CMD="dart analyze"
  elif [[ -z "$ANALYZE_CMD" ]]; then
    ANALYZE_CMD="flutter analyze"
  fi
elif command -v dart &>/dev/null; then
  ANALYZE_CMD="dart analyze"
fi

if [[ -z "$ANALYZE_CMD" ]]; then
  echo "[dart-analyze] WARNING: neither dart nor flutter found in PATH — skipping $FILE_PATH" >&2
  exit 0
fi

# ── run analysis ──────────────────────────────────────────────────────────────

ANALYZE_OUTPUT=""
ANALYZE_EXIT=0
ANALYZE_OUTPUT=$(${ANALYZE_CMD} "$FILE_PATH" 2>&1) || ANALYZE_EXIT=$?

# ── parse and separate errors vs warnings ────────────────────────────────────

ERROR_LINES=$(printf '%s\n' "$ANALYZE_OUTPUT" | grep -i " error " || true)
WARNING_LINES=$(printf '%s\n' "$ANALYZE_OUTPUT" | grep -i " warning \| hint \| info " || true)

ERROR_COUNT=$(printf '%s\n' "$ERROR_LINES" | grep -c . || true)
WARNING_COUNT=$(printf '%s\n' "$WARNING_LINES" | grep -c . || true)

# ── report results ────────────────────────────────────────────────────────────

if [[ $ANALYZE_EXIT -eq 0 ]] && [[ "$ERROR_COUNT" -eq 0 ]] && [[ "$WARNING_COUNT" -eq 0 ]]; then
  echo "[dart-analyze] $FILE_PATH — no analysis issues (tool: $ANALYZE_CMD)"
  exit 0
fi

if [[ "$ERROR_COUNT" -gt 0 ]]; then
  echo "[dart-analyze] ERRORS in $FILE_PATH ($ERROR_COUNT error(s) — must fix):"
  printf '%s\n' "$ERROR_LINES"
  echo ""
fi

if [[ "$WARNING_COUNT" -gt 0 ]]; then
  echo "[dart-analyze] WARNINGS in $FILE_PATH ($WARNING_COUNT warning(s) — review):"
  printf '%s\n' "$WARNING_LINES"
  echo ""
fi

# If analysis exited non-zero but we couldn't parse the structured output, dump everything
if [[ $ANALYZE_EXIT -ne 0 ]] && [[ "$ERROR_COUNT" -eq 0 ]] && [[ "$WARNING_COUNT" -eq 0 ]]; then
  echo "[dart-analyze] Analysis failed for $FILE_PATH (exit $ANALYZE_EXIT):"
  echo "$ANALYZE_OUTPUT"
fi

exit 0
