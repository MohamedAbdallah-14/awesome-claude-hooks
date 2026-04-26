#!/usr/bin/env bash
# Hook name:   test-coverage-check
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a test file, detects the test framework and
#              runs the specific test file so results are immediately visible.
#              Default: OFF (requires CLAUDE_RUN_TESTS_ON_SAVE=1) since test
#              runs can be slow.
#
#              Recognises test files by pattern:
#                *.test.ts  *.spec.ts  *.test.tsx  *.spec.tsx   → jest
#                *.test.js  *.spec.js                            → jest
#                test_*.py  *_test.py                            → pytest
#                *_test.go                                       → go test
#                *_test.dart  *_widget_test.dart                 → dart test
#
# Config (env vars):
#   CLAUDE_RUN_TESTS_ON_SAVE=1   Enable this hook. Default: 0 (disabled).
#   CLAUDE_TEST_TIMEOUT=30       Timeout in seconds for the test run. Default 30.
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
#               "command": "/path/to/hooks/quality/test-coverage-check.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── guard: opt-in only ────────────────────────────────────────────────────────

if [[ "${CLAUDE_RUN_TESTS_ON_SAVE:-0}" != "1" ]]; then
  exit 0
fi

# ── cross-platform timeout wrapper ───────────────────────────────────────────
# macOS ships without GNU timeout; use gtimeout (coreutils) if available, else
# fall back to the bare command (no timeout enforcement).
_timeout() {
  if command -v gtimeout &>/dev/null; then
    gtimeout "$@"
  elif command -v timeout &>/dev/null; then
    timeout "$@"
  else
    shift  # drop the seconds argument
    "$@"
  fi
}

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[test-coverage] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")
TIMEOUT="${CLAUDE_TEST_TIMEOUT:-30}"
FRAMEWORK=""

# ── detect test framework by filename pattern ─────────────────────────────────

case "$BASENAME" in
  *.test.ts|*.spec.ts|*.test.tsx|*.spec.tsx|*.test.js|*.spec.js|*.test.jsx|*.spec.jsx)
    FRAMEWORK="jest"
    ;;
  test_*.py|*_test.py)
    FRAMEWORK="pytest"
    ;;
  *_test.go)
    FRAMEWORK="go"
    ;;
  *_test.dart|*_widget_test.dart)
    FRAMEWORK="dart"
    ;;
  *)
    # Not a test file — skip silently
    exit 0
    ;;
esac

echo "[test-coverage] Test file detected: $BASENAME (framework: $FRAMEWORK)"
echo "[test-coverage] Running tests (timeout: ${TIMEOUT}s)..."

# ── run tests ────────────────────────────────────────────────────────────────

TEST_OUTPUT=""
TEST_EXIT=0
FILE_DIR=$(dirname "$FILE_PATH")

case "$FRAMEWORK" in
  jest)
    JEST_BIN=""
    if [[ -x "$FILE_DIR/node_modules/.bin/jest" ]]; then
      JEST_BIN="$FILE_DIR/node_modules/.bin/jest"
    else
      # Walk up to find node_modules/.bin/jest
      SEARCH_DIR="$FILE_DIR"
      while [[ "$SEARCH_DIR" != "/" ]]; do
        if [[ -x "$SEARCH_DIR/node_modules/.bin/jest" ]]; then
          JEST_BIN="$SEARCH_DIR/node_modules/.bin/jest"
          break
        fi
        SEARCH_DIR=$(dirname "$SEARCH_DIR")
      done
    fi

    if [[ -z "$JEST_BIN" ]] && command -v jest &>/dev/null; then
      JEST_BIN="jest"
    fi

    if [[ -z "$JEST_BIN" ]] && command -v npx &>/dev/null; then
      JEST_BIN="npx jest"
    fi

    if [[ -z "$JEST_BIN" ]]; then
      echo "[test-coverage] WARNING: jest not found — skipping test run" >&2
      exit 0
    fi

    TEST_OUTPUT=$(_timeout "$TIMEOUT" ${JEST_BIN} --no-coverage --testPathPattern="$(basename "$FILE_PATH")" 2>&1) \
      || TEST_EXIT=$?
    ;;

  pytest)
    if ! command -v pytest &>/dev/null; then
      echo "[test-coverage] WARNING: pytest not found — skipping test run" >&2
      exit 0
    fi
    TEST_OUTPUT=$(_timeout "$TIMEOUT" pytest "$FILE_PATH" -v 2>&1) || TEST_EXIT=$?
    ;;

  go)
    if ! command -v go &>/dev/null; then
      echo "[test-coverage] WARNING: go not found in PATH — skipping test run" >&2
      exit 0
    fi
    TEST_OUTPUT=$(cd "$FILE_DIR" && _timeout "$TIMEOUT" go test ./... -v 2>&1) || TEST_EXIT=$?
    ;;

  dart)
    DART_TEST_BIN=""
    if command -v flutter &>/dev/null; then
      DART_TEST_BIN="flutter test"
    elif command -v dart &>/dev/null; then
      DART_TEST_BIN="dart test"
    fi

    if [[ -z "$DART_TEST_BIN" ]]; then
      echo "[test-coverage] WARNING: neither flutter nor dart found in PATH — skipping test run" >&2
      exit 0
    fi

    TEST_OUTPUT=$(_timeout "$TIMEOUT" ${DART_TEST_BIN} "$FILE_PATH" 2>&1) || TEST_EXIT=$?
    ;;
esac

# ── report results ────────────────────────────────────────────────────────────

if [[ $TEST_EXIT -eq 0 ]]; then
  # Extract pass/fail summary line if possible
  SUMMARY=$(printf '%s\n' "$TEST_OUTPUT" | grep -E "passed|failed|Tests:|PASS|FAIL|ok " | tail -5 || true)
  echo "[test-coverage] Tests PASSED for $BASENAME"
  if [[ -n "$SUMMARY" ]]; then
    echo "$SUMMARY"
  fi
elif [[ $TEST_EXIT -eq 124 ]]; then
  echo "[test-coverage] Tests TIMED OUT after ${TIMEOUT}s for $BASENAME"
  echo "[test-coverage]   Increase limit: set CLAUDE_TEST_TIMEOUT=$((TIMEOUT * 2))"
else
  echo "[test-coverage] Tests FAILED for $BASENAME (exit $TEST_EXIT):"
  echo ""
  # Show last 40 lines — failure output is usually at the end
  printf '%s\n' "$TEST_OUTPUT" | tail -40
fi

exit 0
