#!/usr/bin/env bash
# Hook name:   inject-test-results
# Event:       Stop
# Description: After each response, scans for recent test output and writes a
#              summary to ~/.claude/context/test-results.md so Claude knows
#              the current pass/fail state before suggesting the next step.
#
#              Detection order (first match wins):
#              1. $CLAUDE_TEST_RESULTS_FILE  — explicit path to any test output
#              2. jest --json output at common locations (jest-results.json,
#                 test-results.json, coverage/test-results.json)
#              3. pytest --tb=no -q output cached at /tmp/claude-pytest-*.txt
#              4. Generic last-run file at /tmp/claude-test-output.txt
#
# Config (env vars):
#   CLAUDE_TEST_RESULTS_FILE   Path to test output file to parse. Optional.
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
#               "command": "/path/to/hooks/context/inject-test-results.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[inject-test-results] WARNING: jq not found — skipping" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

CONTEXT_DIR="${HOME}/.claude/context"
OUTPUT_FILE="${CONTEXT_DIR}/test-results.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  echo "[inject-test-results] WARNING: invalid JSON on stdin — skipping" >&2
  exit 0
fi

# ── helper: write no-data note ────────────────────────────────────────────────

write_no_data() {
  mkdir -p "$CONTEXT_DIR"
  printf '# Test Results\n\n_Updated: %s_\n\nNo test output found.\n\nTo populate this context:\n- Run Jest with `--json --outputFile=jest-results.json`\n- Run pytest and pipe output to `/tmp/claude-test-output.txt`\n- Set `CLAUDE_TEST_RESULTS_FILE` to point at your test output file\n' \
    "$TIMESTAMP" > "$OUTPUT_FILE"
}

# ── locate test results file ──────────────────────────────────────────────────

RESULTS_FILE=""

# 1. Explicit override
if [[ -n "${CLAUDE_TEST_RESULTS_FILE:-}" ]] && [[ -f "${CLAUDE_TEST_RESULTS_FILE}" ]]; then
  RESULTS_FILE="${CLAUDE_TEST_RESULTS_FILE}"
fi

# 2. Jest --json output (common filenames in CWD or project root)
if [[ -z "$RESULTS_FILE" ]]; then
  for candidate in \
    "${PWD}/jest-results.json" \
    "${PWD}/test-results.json" \
    "${PWD}/coverage/test-results.json" \
    "${PWD}/.jest-test-results.json"; do
    if [[ -f "$candidate" ]]; then
      RESULTS_FILE="$candidate"
      break
    fi
  done
fi

# 3. /tmp generic output file (written by npm test wrapper or pytest)
if [[ -z "$RESULTS_FILE" ]]; then
  for candidate in \
    "/tmp/claude-test-output.txt" \
    "/tmp/claude-pytest-output.txt"; do
    if [[ -f "$candidate" ]]; then
      RESULTS_FILE="$candidate"
      break
    fi
  done
fi

if [[ -z "$RESULTS_FILE" ]]; then
  write_no_data
  exit 0
fi

# ── parse results ─────────────────────────────────────────────────────────────

FILE_MOD_TIME=$(date -r "$RESULTS_FILE" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

# Try Jest JSON format first
IS_JEST_JSON=0
if [[ "$RESULTS_FILE" == *.json ]]; then
  if jq -e '.numTotalTests' "$RESULTS_FILE" &>/dev/null 2>&1; then
    IS_JEST_JSON=1
  fi
fi

mkdir -p "$CONTEXT_DIR"

if [[ "$IS_JEST_JSON" -eq 1 ]]; then
  # Parse Jest --json output
  TOTAL=$(jq -r '.numTotalTests // 0' "$RESULTS_FILE")
  PASSED=$(jq -r '.numPassedTests // 0' "$RESULTS_FILE")
  FAILED=$(jq -r '.numFailedTests // 0' "$RESULTS_FILE")
  SKIPPED=$(jq -r '.numPendingTests // 0' "$RESULTS_FILE")
  SUITES_TOTAL=$(jq -r '.numTotalTestSuites // 0' "$RESULTS_FILE")
  SUITES_FAILED=$(jq -r '.numFailedTestSuites // 0' "$RESULTS_FILE")
  SUCCESS=$(jq -r '.success // false' "$RESULTS_FILE")
  OVERALL=$([ "$SUCCESS" = "true" ] && echo "PASS" || echo "FAIL")

  # Collect failing test names (up to 10)
  FAILING_TESTS=$(jq -r '
    .testResults[]?
    | select(.status == "failed")
    | .testFilePath as $file
    | .testResults[]?
    | select(.status == "failed")
    | "  - \($file | split("/") | last): \(.fullName)"
  ' "$RESULTS_FILE" 2>/dev/null | head -10 || true)

  {
    printf '# Test Results (Jest)\n\n'
    printf '_Updated: %s — file modified: %s_\n\n' "$TIMESTAMP" "$FILE_MOD_TIME"
    printf '**Overall: %s**\n\n' "$OVERALL"
    printf '| Metric | Count |\n|--------|-------|\n'
    printf '| Total tests | %s |\n' "$TOTAL"
    printf '| Passing | %s |\n' "$PASSED"
    printf '| Failing | %s |\n' "$FAILED"
    printf '| Skipped | %s |\n' "$SKIPPED"
    printf '| Test suites | %s total, %s failed |\n\n' "$SUITES_TOTAL" "$SUITES_FAILED"
    if [[ -n "$FAILING_TESTS" ]]; then
      printf '## Failing Tests\n\n```\n%s\n```\n\n' "$FAILING_TESTS"
    fi
  } > "$OUTPUT_FILE"

else
  # Generic text output — try to extract pytest-style summary line
  # pytest outputs "X passed, Y failed, Z skipped" near end of output
  SUMMARY_LINE=$(grep -E '(passed|failed|error)' "$RESULTS_FILE" | tail -3 || true)
  TAIL_OUTPUT=$(tail -20 "$RESULTS_FILE" || true)

  {
    printf '# Test Results\n\n'
    printf '_Updated: %s — file modified: %s_\n\n' "$TIMESTAMP" "$FILE_MOD_TIME"
    printf 'Source: `%s`\n\n' "$RESULTS_FILE"
    if [[ -n "$SUMMARY_LINE" ]]; then
      printf '## Summary Lines\n\n```\n%s\n```\n\n' "$SUMMARY_LINE"
    fi
    printf '## Last 20 Lines of Output\n\n```\n%s\n```\n' "$TAIL_OUTPUT"
  } > "$OUTPUT_FILE"
fi

exit 0
