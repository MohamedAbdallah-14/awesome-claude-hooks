#!/usr/bin/env bash
# Hook name:   prettier-gate
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a supported file, checks formatting with
#              Prettier. By default reports the diff so Claude can see what
#              needs to change. With CLAUDE_PRETTIER_AUTO_FIX=1, silently
#              applies prettier --write instead.
#
#              Matches: .js  .jsx  .ts  .tsx  .css  .json  .md
#
# Config (env vars):
#   CLAUDE_PRETTIER_AUTO_FIX=1   Run `prettier --write` automatically instead
#                                of just checking. Default: 0 (check only).
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
#               "command": "/path/to/hooks/quality/prettier-gate.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[prettier-gate] WARNING: jq not found — install it with: brew install jq" >&2
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
  *.js|*.jsx|*.ts|*.tsx|*.css|*.json|*.md) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── prettier availability ─────────────────────────────────────────────────────

PRETTIER_BIN=""
if command -v prettier &>/dev/null; then
  PRETTIER_BIN="prettier"
elif [[ -x "$(dirname "$FILE_PATH")/node_modules/.bin/prettier" ]]; then
  PRETTIER_BIN="$(dirname "$FILE_PATH")/node_modules/.bin/prettier"
elif command -v npx &>/dev/null && npx --no-install prettier --version &>/dev/null 2>&1; then
  PRETTIER_BIN="npx prettier"
fi

if [[ -z "$PRETTIER_BIN" ]]; then
  echo "[prettier-gate] WARNING: prettier not found — skipping format check for $FILE_PATH" >&2
  exit 0
fi

# ── auto-fix mode ─────────────────────────────────────────────────────────────

if [[ "${CLAUDE_PRETTIER_AUTO_FIX:-0}" == "1" ]]; then
  ${PRETTIER_BIN} --write "$FILE_PATH" &>/dev/null
  echo "[prettier-gate] Auto-formatted $FILE_PATH"
  exit 0
fi

# ── check mode: run prettier --check and show diff ───────────────────────────

CHECK_EXIT=0
${PRETTIER_BIN} --check "$FILE_PATH" &>/dev/null || CHECK_EXIT=$?

if [[ $CHECK_EXIT -eq 0 ]]; then
  echo "[prettier-gate] $FILE_PATH — formatting looks good"
  exit 0
fi

# Generate a unified diff of what prettier would change
ORIGINAL=$(cat "$FILE_PATH")
FORMATTED=$(${PRETTIER_BIN} "$FILE_PATH" 2>/dev/null) || true

if command -v diff &>/dev/null; then
  DIFF_OUTPUT=$(diff --unified=3 \
    <(printf '%s\n' "$ORIGINAL") \
    <(printf '%s\n' "$FORMATTED") \
    --label "current" \
    --label "prettier" \
    2>/dev/null) || true
fi

echo "[prettier-gate] $FILE_PATH is not formatted. Diff (current → prettier):"
echo "${DIFF_OUTPUT:-  (diff unavailable — run: ${PRETTIER_BIN} --write $FILE_PATH)}"
echo ""
echo "[prettier-gate] To fix: ${PRETTIER_BIN} --write $FILE_PATH"
echo "[prettier-gate] To auto-fix on every save: set CLAUDE_PRETTIER_AUTO_FIX=1"

exit 0
