#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/context/inject-recent-commits.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "v1" > a.txt
  git add a.txt
  git commit -q -m "first commit"
  echo "v2" > a.txt
  git commit -qa -m "second commit"
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

edit_payload() {
  local fp="$1"
  jq -n --arg p "$fp" \
    '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Edit",tool_input:{file_path:$p,old_string:"",new_string:""}}'
}

@test "happy path: tracked file yields commit log context" {
  payload=$(edit_payload "${WORK}/a.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (.context | type == "string")' >/dev/null
  printf '%s' "$output" | jq -r '.context' | grep -qi "first commit\|second commit"
}

@test "silent skip: untracked file approves without context" {
  echo "z" > "${WORK}/untracked.txt"
  payload=$(edit_payload "${WORK}/untracked.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (has("context") | not)' >/dev/null
}

@test "silent skip: file outside any git repo approves" {
  NONGIT=$(mktemp -d)
  echo "x" > "${NONGIT}/loose.txt"
  payload=$(edit_payload "${NONGIT}/loose.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$NONGIT' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (has("context") | not)' >/dev/null
  rm -rf "$NONGIT"
}

@test "silent skip: empty file_path approves" {
  payload=$(jq -n '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Edit",tool_input:{}}')
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
}

@test "respects CLAUDE_GIT_LOG_COUNT (1 entry only)" {
  payload=$(edit_payload "${WORK}/a.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_GIT_LOG_COUNT=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.context' | grep -q "last 1 commits"
}
