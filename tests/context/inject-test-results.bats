#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/context/inject-test-results.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

stop_payload() {
  jq -n '{hook_event_name:"Stop",session_id:"t",stop_hook_active:false}'
}

@test "happy path: parses Jest --json output and writes summary" {
  cat > "${WORK}/jest-results.json" <<'EOF'
{
  "numTotalTests": 10,
  "numPassedTests": 8,
  "numFailedTests": 2,
  "numPendingTests": 0,
  "numTotalTestSuites": 3,
  "numFailedTestSuites": 1,
  "success": false,
  "testResults": []
}
EOF
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  out="${TMPHOME}/.claude/context/test-results.md"
  [ -f "$out" ]
  grep -q "Test Results (Jest)" "$out"
  grep -q "FAIL" "$out"
  grep -q "| Total tests | 10 |" "$out"
}

@test "silent skip: writes 'no test output' note when nothing is found" {
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  out="${TMPHOME}/.claude/context/test-results.md"
  [ -f "$out" ]
  grep -q "No test output found" "$out"
}

@test "respects CLAUDE_TEST_RESULTS_FILE override" {
  custom="${WORK}/my-test-output.txt"
  printf 'tests run\n5 passed, 1 failed in 2.3s\n' > "$custom"

  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_TEST_RESULTS_FILE="$custom" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  out="${TMPHOME}/.claude/context/test-results.md"
  [ -f "$out" ]
  grep -qF "$custom" "$out"
  grep -q "5 passed, 1 failed" "$out"
}

@test "exits 0 with warning on invalid JSON stdin" {
  pfile=$(mktemp); printf 'garbage' > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ ! -f "${TMPHOME}/.claude/context/test-results.md" ]
}
