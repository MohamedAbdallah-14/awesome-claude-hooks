#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/git/conflict-detector.sh"

setup() {
  TMP_DIR=$(mktemp -d)
  CLEAN_FILE="$TMP_DIR/clean.txt"
  CONFLICT_FILE="$TMP_DIR/conflicted.txt"
  printf 'hello\nworld\n' > "$CLEAN_FILE"
  printf 'line1\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\nline2\n' > "$CONFLICT_FILE"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "allows edit on clean file" {
  payload=$(pretool_payload Edit "$CLEAN_FILE" "new content")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows edit on non-existent file (Write of new file)" {
  payload=$(pretool_payload Write "$TMP_DIR/new.txt" "fresh content")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "default mode: warns but allows edit on conflicted file" {
  payload=$(pretool_payload Edit "$CONFLICT_FILE" "patched")
  run_hook "$HOOK" "$payload"
  # Default behavior is approve (with context). Status 0, not a deny.
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "expected approve, got deny: $output" >&2
    return 1
  fi
}

@test "blocks conflicted file when CLAUDE_BLOCK_CONFLICT_EDITS=1" {
  payload=$(pretool_payload Edit "$CONFLICT_FILE" "patched")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run bash -c "CLAUDE_BLOCK_CONFLICT_EDITS=1 bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_blocked
  [[ "$output" == *"conflict"* ]]
}

@test "bypass via CLAUDE_CONFLICT_SKIP=1" {
  payload=$(pretool_payload Edit "$CONFLICT_FILE" "patched")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run bash -c "CLAUDE_BLOCK_CONFLICT_EDITS=1 CLAUDE_CONFLICT_SKIP=1 bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "Write tool: blocks conflicted target when CLAUDE_BLOCK_CONFLICT_EDITS=1" {
  payload=$(pretool_payload Write "$CONFLICT_FILE" "overwrite")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run bash -c "CLAUDE_BLOCK_CONFLICT_EDITS=1 bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_blocked
}

@test "ignores non-Edit/Write/MultiEdit tools" {
  payload=$(pretool_payload Bash "cat $CONFLICT_FILE" "")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
