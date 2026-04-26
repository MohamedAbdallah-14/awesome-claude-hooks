#!/usr/bin/env bash
# Hook name:   auto-format-on-save
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: Universal formatter. Detects the file type and runs the
#              appropriate formatter. Falls back gracefully if the formatter
#              is not installed — never blocks Claude.
#
#              Formatter selection by extension:
#                .js .jsx .ts .tsx  → prettier (then eslint --fix as fallback)
#                .py                → black (then autopep8, then ruff format)
#                .go                → gofmt -w
#                .dart              → dart format
#                .rs                → rustfmt
#                .sh .bash          → shfmt -w
#
# Config (env vars):
#   CLAUDE_AUTOFORMAT_ENABLED=1       Set to 0 to disable (opt-out, default ON).
#   CLAUDE_AUTOFORMAT_SKIP_TYPES      Colon-separated extensions to skip.
#                                     Example: "py:rs" skips Python and Rust.
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
#               "command": "/path/to/hooks/automation/auto-format-on-save.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── enabled gate ──────────────────────────────────────────────────────────────

if [[ "${CLAUDE_AUTOFORMAT_ENABLED:-1}" != "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-format-on-save] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

FILE_EXT="${FILE_PATH##*.}"

# ── skip-type check ───────────────────────────────────────────────────────────

SKIP_TYPES="${CLAUDE_AUTOFORMAT_SKIP_TYPES:-}"
if [[ -n "$SKIP_TYPES" ]]; then
  IFS=':' read -ra SKIP_LIST <<< "$SKIP_TYPES"
  for SKIP in "${SKIP_LIST[@]}"; do
    # strip leading dot if user included it
    SKIP="${SKIP#.}"
    if [[ "$FILE_EXT" == "$SKIP" ]]; then
      echo "[auto-format-on-save] Skipping $FILE_PATH (extension .$FILE_EXT in skip list)"
      exit 0
    fi
  done
fi

# ── skip vendored / generated paths ──────────────────────────────────────────

case "$FILE_PATH" in
  */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/vendor/*|*/target/*) exit 0 ;;
esac

# ── resolve project root (best effort) ───────────────────────────────────────

PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")

# ── formatters ────────────────────────────────────────────────────────────────

run_format() {
  local label="$1"; shift
  local exit_code=0
  "$@" 2>&1 || exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    echo "[auto-format-on-save] Formatted $FILE_PATH with $label"
  else
    echo "[auto-format-on-save] WARNING: $label exited $exit_code for $FILE_PATH" >&2
  fi
}

# ── JS / TS / JSX / TSX ──────────────────────────────────────────────────────

case "$FILE_EXT" in
  js|jsx|ts|tsx)
    # prefer project-local prettier
    LOCAL_PRETTIER="$PROJECT_ROOT/node_modules/.bin/prettier"
    if [[ -x "$LOCAL_PRETTIER" ]]; then
      run_format "prettier" "$LOCAL_PRETTIER" --write "$FILE_PATH"
    elif command -v prettier &>/dev/null; then
      run_format "prettier" prettier --write "$FILE_PATH"
    elif command -v npx &>/dev/null && npx --no-install prettier --version &>/dev/null 2>&1; then
      run_format "prettier (npx)" npx prettier --write "$FILE_PATH"
    else
      # fallback: eslint --fix
      LOCAL_ESLINT="$PROJECT_ROOT/node_modules/.bin/eslint"
      if [[ -x "$LOCAL_ESLINT" ]]; then
        run_format "eslint --fix" "$LOCAL_ESLINT" --fix "$FILE_PATH"
      elif command -v eslint &>/dev/null; then
        run_format "eslint --fix" eslint --fix "$FILE_PATH"
      else
        echo "[auto-format-on-save] WARNING: no formatter found for $FILE_PATH (tried prettier, eslint)" >&2
      fi
    fi
    ;;

# ── Python ───────────────────────────────────────────────────────────────────

  py)
    if command -v black &>/dev/null; then
      run_format "black" black --quiet "$FILE_PATH"
    elif command -v ruff &>/dev/null; then
      run_format "ruff format" ruff format "$FILE_PATH"
    elif command -v autopep8 &>/dev/null; then
      run_format "autopep8" autopep8 --in-place "$FILE_PATH"
    else
      echo "[auto-format-on-save] WARNING: no Python formatter found for $FILE_PATH (tried black, ruff, autopep8)" >&2
    fi
    ;;

# ── Go ────────────────────────────────────────────────────────────────────────

  go)
    if command -v gofmt &>/dev/null; then
      run_format "gofmt" gofmt -w "$FILE_PATH"
    else
      echo "[auto-format-on-save] WARNING: gofmt not found — skipping $FILE_PATH" >&2
    fi
    ;;

# ── Dart ─────────────────────────────────────────────────────────────────────

  dart)
    if command -v dart &>/dev/null; then
      run_format "dart format" dart format "$FILE_PATH"
    else
      echo "[auto-format-on-save] WARNING: dart not found — skipping $FILE_PATH" >&2
    fi
    ;;

# ── Rust ─────────────────────────────────────────────────────────────────────

  rs)
    if command -v rustfmt &>/dev/null; then
      run_format "rustfmt" rustfmt "$FILE_PATH"
    else
      echo "[auto-format-on-save] WARNING: rustfmt not found — skipping $FILE_PATH" >&2
      echo "[auto-format-on-save] Install: rustup component add rustfmt" >&2
    fi
    ;;

# ── Shell ─────────────────────────────────────────────────────────────────────

  sh|bash)
    if command -v shfmt &>/dev/null; then
      run_format "shfmt" shfmt -w "$FILE_PATH"
    else
      echo "[auto-format-on-save] WARNING: shfmt not found — skipping $FILE_PATH" >&2
      echo "[auto-format-on-save] Install: brew install shfmt" >&2
    fi
    ;;

# ── unknown type — skip silently ──────────────────────────────────────────────

  *)
    exit 0
    ;;
esac

exit 0
