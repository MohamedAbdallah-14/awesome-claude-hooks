#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/automation/auto-run-tests.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

posttool_payload() {
  local fp="$1"
  jq -n --arg p "$fp" \
    '{hook_event_name:"PostToolUse",session_id:"t",tool_name:"Write",tool_input:{file_path:$p}}'
}

@test "opt-in gate: disabled by default — exits 0 silently" {
  echo "def x(): pass" > "${WORK}/a.py"
  echo "def test_x(): pass" > "${WORK}/test_a.py"
  payload=$(posttool_payload "${WORK}/a.py")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent skip: enabled, file is itself a test file" {
  echo "def test_x(): pass" > "${WORK}/test_a.py"
  payload=$(posttool_payload "${WORK}/test_a.py")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_TEST_ENABLED=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent skip: enabled but no related test file exists" {
  echo "def x(): pass" > "${WORK}/a.py"
  payload=$(posttool_payload "${WORK}/a.py")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_TEST_ENABLED=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
}

@test "silent skip: enabled but file does not exist" {
  payload=$(posttool_payload "${WORK}/missing.go")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_TEST_ENABLED=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent skip: enabled .ts file but no jest config — exits 0" {
  echo "export const x = 1" > "${WORK}/a.ts"
  echo "test('x', () => {})" > "${WORK}/a.test.ts"
  payload=$(posttool_payload "${WORK}/a.ts")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_TEST_ENABLED=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
