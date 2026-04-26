#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   auto-prettier
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: Automatically runs prettier --write on JS/TS/CSS/JSON/MD files
#              after Claude writes or edits them. Keeps code consistently
#              formatted without a separate formatting pass.
#
#              Matches: .js  .jsx  .ts  .tsx  .css  .scss  .json  .md  .mdx  .yaml  .yml
#
# Config (env vars):
#   CLAUDE_PRETTIER_SKIP_PATTERNS   Colon-separated glob patterns to skip.
#                                   Default: "node_modules:dist:build:.next:vendor"
#                                   Example: "node_modules:dist:build:.next:vendor:generated"
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
#               "command": "/path/to/hooks/automation/auto-prettier.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-prettier] WARNING: jq not found — install it with: brew install jq" >&2
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
  *.js|*.jsx|*.ts|*.tsx|*.css|*.scss|*.json|*.md|*.mdx|*.yaml|*.yml) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── skip-pattern check ────────────────────────────────────────────────────────

SKIP_PATTERNS="${CLAUDE_PRETTIER_SKIP_PATTERNS:-node_modules:dist:build:.next:vendor}"

IFS=':' read -ra PATTERNS <<< "$SKIP_PATTERNS"
for PATTERN in "${PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == *"$PATTERN"* ]]; then
    echo "[auto-prettier] Skipping $FILE_PATH (matches skip pattern: $PATTERN)"
    exit 0
  fi
done

# ── resolve prettier binary ───────────────────────────────────────────────────

PRETTIER_BIN=""

# prefer local project binary
PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")
LOCAL_BIN="$PROJECT_ROOT/node_modules/.bin/prettier"

if [[ -x "$LOCAL_BIN" ]]; then
  PRETTIER_BIN="$LOCAL_BIN"
elif command -v prettier &>/dev/null; then
  PRETTIER_BIN="prettier"
elif command -v npx &>/dev/null; then
  # check if prettier is available via npx without installing
  if npx --no-install prettier --version &>/dev/null 2>&1; then
    PRETTIER_BIN="npx prettier"
  fi
fi

if [[ -z "$PRETTIER_BIN" ]]; then
  echo "[auto-prettier] WARNING: prettier not found — skipping format for $FILE_PATH" >&2
  echo "[auto-prettier] Install: npm install --save-dev prettier" >&2
  exit 0
fi

# ── check for prettier config (respect project opt-out) ───────────────────────

# If no prettier config in project, still run but only with default options
# to avoid overriding intentional absence of prettier

# ── run prettier ─────────────────────────────────────────────────────────────

FORMAT_EXIT=0
FORMAT_OUTPUT=$(${PRETTIER_BIN} --write "$FILE_PATH" 2>&1) || FORMAT_EXIT=$?

if [[ $FORMAT_EXIT -eq 0 ]]; then
  echo "[auto-prettier] Formatted $FILE_PATH with prettier"
else
  echo "[auto-prettier] WARNING: prettier exited with code $FORMAT_EXIT for $FILE_PATH" >&2
  echo "$FORMAT_OUTPUT" >&2
fi

exit 0
