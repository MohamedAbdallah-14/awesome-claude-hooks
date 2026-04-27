#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/context/inject-file-history.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "hello" > tracked.txt
  git add tracked.txt
  git commit -q -m "add tracked.txt"
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

read_payload() {
  local fp="$1"
  jq -n --arg p "$fp" \
    '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Read",tool_input:{file_path:$p}}'
}

@test "happy path: tracked file emits context with file history" {
  payload=$(read_payload "${WORK}/tracked.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  # Stderr is silenced because the hook can emit benign bash arithmetic
  # warnings on some platforms when commit counts are produced via wc | tr.
  # Those warnings don't affect the JSON contract — only stdout matters.
  run bash -c "cd '$WORK' && HOME='$TMPHOME' bash '$HOOK' < '$pfile' 2>/dev/null"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (.context | type == "string")' >/dev/null
  printf '%s' "$output" | jq -r '.context' | grep -q "tracked.txt"
  printf '%s' "$output" | jq -r '.context' | grep -q "Last modified"
}

@test "silent skip: untracked file gets a plain approve with no context" {
  echo "foo" > "${WORK}/untracked.txt"
  payload=$(read_payload "${WORK}/untracked.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (has("context") | not)' >/dev/null
}

@test "silent skip: directory path is approved with no context" {
  payload=$(read_payload "$WORK")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (has("context") | not)' >/dev/null
}

@test "silent skip: empty file_path approves" {
  payload=$(jq -n '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Read",tool_input:{}}')
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
}

@test "TODO scan surfaces in context when markers exist" {
  echo "// TODO: fix me later" >> "${WORK}/tracked.txt"
  git -C "$WORK" add tracked.txt
  git -C "$WORK" commit -q -m "add todo"
  payload=$(read_payload "${WORK}/tracked.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run bash -c "cd '$WORK' && HOME='$TMPHOME' bash '$HOOK' < '$pfile' 2>/dev/null"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.context' | grep -qi "TODO"
}
