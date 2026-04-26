#!/usr/bin/env bash
# Hook name:   python-lint
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .py file, runs the best available Python
#              linter/formatter and reports any issues. Tool preference order:
#              ruff (fast, modern) → flake8 (classic) → black --check (format).
#              Reports issues clearly so Claude can fix them.
#
#              Matches: .py
#
# Config (env vars):
#   CLAUDE_PYTHON_LINTER=ruff    Override tool selection. Accepts: ruff, flake8,
#                                black. Skips availability detection.
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
#               "command": "/path/to/hooks/quality/python-lint.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[python-lint] WARNING: jq not found — install it with: brew install jq" >&2
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
  *.py) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── tool selection ────────────────────────────────────────────────────────────

LINTER=""

if [[ -n "${CLAUDE_PYTHON_LINTER:-}" ]]; then
  # Honour explicit override; fail loudly if the tool isn't installed.
  if ! command -v "$CLAUDE_PYTHON_LINTER" &>/dev/null; then
    echo "[python-lint] WARNING: CLAUDE_PYTHON_LINTER=$CLAUDE_PYTHON_LINTER is set but not found in PATH — skipping" >&2
    exit 0
  fi
  LINTER="$CLAUDE_PYTHON_LINTER"
else
  # Auto-detect: prefer ruff > flake8 > black
  if command -v ruff &>/dev/null; then
    LINTER="ruff"
  elif command -v flake8 &>/dev/null; then
    LINTER="flake8"
  elif command -v black &>/dev/null; then
    LINTER="black"
  fi
fi

if [[ -z "$LINTER" ]]; then
  echo "[python-lint] WARNING: no Python linter found (install ruff, flake8, or black) — skipping $FILE_PATH" >&2
  exit 0
fi

# ── run linter ────────────────────────────────────────────────────────────────

LINT_OUTPUT=""
LINT_EXIT=0

case "$LINTER" in
  ruff)
    LINT_OUTPUT=$(ruff check "$FILE_PATH" 2>&1) || LINT_EXIT=$?
    ;;
  flake8)
    LINT_OUTPUT=$(flake8 "$FILE_PATH" 2>&1) || LINT_EXIT=$?
    ;;
  black)
    LINT_OUTPUT=$(black --check --diff "$FILE_PATH" 2>&1) || LINT_EXIT=$?
    ;;
esac

# ── report results ────────────────────────────────────────────────────────────

if [[ $LINT_EXIT -eq 0 ]]; then
  echo "[python-lint] $FILE_PATH — no issues found (tool: $LINTER)"
else
  echo "[python-lint] $LINTER found issues in $FILE_PATH:"
  echo "$LINT_OUTPUT"
  echo ""
  case "$LINTER" in
    ruff)   echo "[python-lint] To auto-fix: ruff check --fix $FILE_PATH" ;;
    flake8) echo "[python-lint] flake8 does not auto-fix. Address the issues manually." ;;
    black)  echo "[python-lint] To auto-fix: black $FILE_PATH" ;;
  esac
fi

exit 0
