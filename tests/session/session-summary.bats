#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/session/session-summary.sh"

setup() {
  TMP_HOME=$(mktemp -d)
  TRANSCRIPT=$(mktemp)
  printf '%s\n' \
    '{"type":"tool_use","name":"Read"}' \
    '{"type":"tool_use","name":"Bash"}' \
    '{"type":"text","text":"hi"}' \
    > "$TRANSCRIPT"
}

teardown() {
  rm -rf "$TMP_HOME"
  rm -f "$TRANSCRIPT"
}

@test "session-summary: appends a line to today's daily log" {
  payload=$(jq -n --arg t "$TRANSCRIPT" --arg c "$PWD" \
    '{hook_event_name:"Stop",cwd:$c,transcript_path:$t}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  LOG="${TMP_HOME}/.claude/sessions/$(date +%Y-%m-%d).md"
  [ -f "$LOG" ]
  grep -q "tool calls" "$LOG"
  grep -q "2 tool calls" "$LOG"
}

@test "session-summary: works when transcript is missing (zero tool calls)" {
  payload=$(jq -n --arg c "$PWD" '{hook_event_name:"Stop",cwd:$c,transcript_path:"/no/file"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  LOG="${TMP_HOME}/.claude/sessions/$(date +%Y-%m-%d).md"
  [ -f "$LOG" ]
  grep -q "0 tool calls" "$LOG"
}

@test "session-summary: never writes JSON to stdout" {
  payload=$(jq -n --arg t "$TRANSCRIPT" --arg c "$PWD" \
    '{hook_event_name:"Stop",cwd:$c,transcript_path:$t}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
