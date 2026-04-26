#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   auto-run-tests
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a source file, finds the related test file
#              by convention and runs it. Supports Jest (TS/JS), pytest (Python),
#              Go test, and Dart/Flutter test.
#
#              Test discovery conventions:
#                foo.ts        → foo.test.ts  or  __tests__/foo.test.ts
#                foo.py        → test_foo.py  or  foo_test.py  or  tests/test_foo.py
#                foo.go        → foo_test.go  (same directory)
#                foo.dart      → foo_test.dart  or  test/foo_test.dart
#
#              Only runs if the related test file actually exists.
#              Does NOT run tests for test files themselves (avoids double runs).
#
# Config (env vars):
#   CLAUDE_AUTO_TEST_ENABLED=0   Set to 1 to enable (opt-in, default OFF).
#   CLAUDE_AUTO_TEST_TIMEOUT=60  Seconds before test run is killed. Default 60.
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
#               "command": "/path/to/hooks/automation/auto-run-tests.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── opt-in gate ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_AUTO_TEST_ENABLED:-0}" != "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-run-tests] WARNING: jq not found — install it with: brew install jq" >&2
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

TIMEOUT="${CLAUDE_AUTO_TEST_TIMEOUT:-60}"
FILE_DIR=$(dirname "$FILE_PATH")
FILE_BASE=$(basename "$FILE_PATH")
FILE_NAME="${FILE_BASE%.*}"   # strip extension
FILE_EXT="${FILE_BASE##*.}"   # just the extension

# ── skip test files themselves ────────────────────────────────────────────────

case "$FILE_BASE" in
  *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) exit 0 ;;
  test_*.py|*_test.py) exit 0 ;;
  *_test.go) exit 0 ;;
  *_test.dart) exit 0 ;;
esac

# ── helpers ───────────────────────────────────────────────────────────────────

run_with_timeout() {
  local label="$1"; shift
  local exit_code=0
  if command -v timeout &>/dev/null; then
    timeout "$TIMEOUT" "$@" || exit_code=$?
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$TIMEOUT" "$@" || exit_code=$?
  else
    "$@" || exit_code=$?
  fi
  if [[ $exit_code -eq 124 ]]; then
    echo "[auto-run-tests] WARNING: $label timed out after ${TIMEOUT}s" >&2
  fi
  return $exit_code
}

# ── TypeScript / JavaScript (Jest) ────────────────────────────────────────────

if [[ "$FILE_EXT" == "ts" || "$FILE_EXT" == "tsx" || "$FILE_EXT" == "js" || "$FILE_EXT" == "jsx" ]]; then
  # find jest config
  PROJECT_ROOT=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$FILE_DIR")
  JEST_CONFIG=""
  for cfg in jest.config.ts jest.config.js jest.config.mjs jest.config.cjs; do
    if [[ -f "$PROJECT_ROOT/$cfg" ]]; then
      JEST_CONFIG="$PROJECT_ROOT/$cfg"
      break
    fi
  done

  if [[ -z "$JEST_CONFIG" ]]; then
    exit 0
  fi

  # find related test
  RELATED_TEST=""
  for candidate in \
    "$FILE_DIR/${FILE_NAME}.test.${FILE_EXT}" \
    "$FILE_DIR/${FILE_NAME}.spec.${FILE_EXT}" \
    "$FILE_DIR/__tests__/${FILE_NAME}.test.${FILE_EXT}" \
    "$FILE_DIR/__tests__/${FILE_NAME}.spec.${FILE_EXT}"; do
    if [[ -f "$candidate" ]]; then
      RELATED_TEST="$candidate"
      break
    fi
  done

  # also check stripping tsx→ts for the test lookup
  if [[ -z "$RELATED_TEST" && ("$FILE_EXT" == "tsx" || "$FILE_EXT" == "jsx") ]]; then
    BASE_EXT="${FILE_EXT%x}"  # tsx→ts, jsx→js
    for candidate in \
      "$FILE_DIR/${FILE_NAME}.test.${BASE_EXT}" \
      "$FILE_DIR/__tests__/${FILE_NAME}.test.${BASE_EXT}"; do
      if [[ -f "$candidate" ]]; then
        RELATED_TEST="$candidate"
        break
      fi
    done
  fi

  if [[ -z "$RELATED_TEST" ]]; then
    exit 0
  fi

  JEST_BIN=""
  if [[ -x "$PROJECT_ROOT/node_modules/.bin/jest" ]]; then
    JEST_BIN="$PROJECT_ROOT/node_modules/.bin/jest"
  elif command -v jest &>/dev/null; then
    JEST_BIN="jest"
  elif command -v npx &>/dev/null; then
    JEST_BIN="npx jest"
  fi

  if [[ -z "$JEST_BIN" ]]; then
    echo "[auto-run-tests] WARNING: jest not found — skipping test for $FILE_PATH" >&2
    exit 0
  fi

  echo "[auto-run-tests] Running Jest for $RELATED_TEST"
  TEST_EXIT=0
  run_with_timeout "jest" ${JEST_BIN} --testPathPattern="$RELATED_TEST" --passWithNoTests 2>&1 || TEST_EXIT=$?

  if [[ $TEST_EXIT -eq 0 ]]; then
    echo "[auto-run-tests] Tests passed for $FILE_PATH"
  else
    echo "[auto-run-tests] Tests FAILED for $FILE_PATH (exit $TEST_EXIT)"
  fi
  exit 0
fi

# ── Python (pytest) ───────────────────────────────────────────────────────────

if [[ "$FILE_EXT" == "py" ]]; then
  if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    exit 0
  fi
  PYTHON_BIN=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)

  # check pytest available
  if ! "$PYTHON_BIN" -m pytest --version &>/dev/null 2>&1; then
    exit 0
  fi

  RELATED_TEST=""
  for candidate in \
    "$FILE_DIR/test_${FILE_NAME}.py" \
    "$FILE_DIR/${FILE_NAME}_test.py" \
    "$FILE_DIR/tests/test_${FILE_NAME}.py" \
    "$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$FILE_DIR")/tests/test_${FILE_NAME}.py"; do
    if [[ -f "$candidate" ]]; then
      RELATED_TEST="$candidate"
      break
    fi
  done

  if [[ -z "$RELATED_TEST" ]]; then
    exit 0
  fi

  echo "[auto-run-tests] Running pytest for $RELATED_TEST"
  TEST_EXIT=0
  run_with_timeout "pytest" "$PYTHON_BIN" -m pytest "$RELATED_TEST" -x --quiet 2>&1 || TEST_EXIT=$?

  if [[ $TEST_EXIT -eq 0 ]]; then
    echo "[auto-run-tests] Tests passed for $FILE_PATH"
  else
    echo "[auto-run-tests] Tests FAILED for $FILE_PATH (exit $TEST_EXIT)"
  fi
  exit 0
fi

# ── Go ────────────────────────────────────────────────────────────────────────

if [[ "$FILE_EXT" == "go" ]]; then
  if ! command -v go &>/dev/null; then
    exit 0
  fi

  # Go test file must exist alongside source
  TEST_FILE="$FILE_DIR/${FILE_NAME}_test.go"
  if [[ ! -f "$TEST_FILE" ]]; then
    exit 0
  fi

  echo "[auto-run-tests] Running go test for $FILE_DIR"
  TEST_EXIT=0
  run_with_timeout "go test" go test "./$FILE_DIR/..." -run . -count=1 2>&1 || TEST_EXIT=$?

  if [[ $TEST_EXIT -eq 0 ]]; then
    echo "[auto-run-tests] Tests passed for $FILE_PATH"
  else
    echo "[auto-run-tests] Tests FAILED for $FILE_PATH (exit $TEST_EXIT)"
  fi
  exit 0
fi

# ── Dart / Flutter ────────────────────────────────────────────────────────────

if [[ "$FILE_EXT" == "dart" ]]; then
  RELATED_TEST=""

  # look for test file in test/ mirroring lib/
  PROJECT_ROOT=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$FILE_DIR")
  # strip the lib/ prefix if present and look in test/
  RELATIVE="${FILE_PATH#$PROJECT_ROOT/lib/}"
  TEST_CANDIDATE="$PROJECT_ROOT/test/${RELATIVE%.dart}_test.dart"

  if [[ -f "$TEST_CANDIDATE" ]]; then
    RELATED_TEST="$TEST_CANDIDATE"
  elif [[ -f "$FILE_DIR/${FILE_NAME}_test.dart" ]]; then
    RELATED_TEST="$FILE_DIR/${FILE_NAME}_test.dart"
  fi

  if [[ -z "$RELATED_TEST" ]]; then
    exit 0
  fi

  if command -v flutter &>/dev/null && [[ -f "$PROJECT_ROOT/pubspec.yaml" ]]; then
    echo "[auto-run-tests] Running flutter test for $RELATED_TEST"
    TEST_EXIT=0
    (cd "$PROJECT_ROOT" && run_with_timeout "flutter test" flutter test "$RELATED_TEST" 2>&1) || TEST_EXIT=$?
  elif command -v dart &>/dev/null; then
    echo "[auto-run-tests] Running dart test for $RELATED_TEST"
    TEST_EXIT=0
    (cd "$PROJECT_ROOT" && run_with_timeout "dart test" dart test "$RELATED_TEST" 2>&1) || TEST_EXIT=$?
  else
    exit 0
  fi

  if [[ $TEST_EXIT -eq 0 ]]; then
    echo "[auto-run-tests] Tests passed for $FILE_PATH"
  else
    echo "[auto-run-tests] Tests FAILED for $FILE_PATH (exit $TEST_EXIT)"
  fi
  exit 0
fi

exit 0
