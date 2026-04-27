#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/cost/session-timer.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  SID="session-timer-test-$$-$RANDOM"
  START_FILE="/tmp/claude-session-${SID}.start"
  COUNT_FILE="/tmp/claude-session-${SID}.count"
  rm -f "$START_FILE" "$COUNT_FILE"
}

teardown() {
  rm -rf "$TMPHOME"
  rm -f "$START_FILE" "$COUNT_FILE"
}

pre_payload() {
  jq -n --arg s "$SID" \
    '{hook_event_name:"PreToolUse",session_id:$s,tool_name:"Bash",tool_input:{command:"x"}}'
}

stop_payload() {
  jq -n --arg s "$SID" \
    '{hook_event_name:"Stop",session_id:$s,stop_hook_active:false}'
}

@test "PreToolUse: creates start file and increments count file" {
  payload=$(pre_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "bash '$HOOK' < '$pfile'"
  [ "$status" -eq 0 ]

  run env HOME="$TMPHOME" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]

  [ -f "$START_FILE" ]
  [ -f "$COUNT_FILE" ]
  [ "$(cat "$COUNT_FILE")" = "2" ]
}

@test "Stop: writes session log line with duration + tool count, then cleans up" {
  # Pretend a session ran by seeding the start/count files.
  printf '%d\n' "$(( $(date +%s) - 30 ))" > "$START_FILE"
  printf '7\n' > "$COUNT_FILE"

  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  log="${TMPHOME}/.claude/sessions.log"
  [ -f "$log" ]
  grep -q "$SID" "$log"
  grep -qE "\| 7$" "$log"
  # Cleanup happened
  [ ! -f "$START_FILE" ]
  [ ! -f "$COUNT_FILE" ]
}

@test "respects CLAUDE_SESSION_LOG override" {
  custom="${TMPHOME}/sess-custom.log"
  printf '%d\n' "$(date +%s)" > "$START_FILE"
  printf '1\n' > "$COUNT_FILE"

  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_SESSION_LOG="$custom" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "$custom" ]
  grep -q "$SID" "$custom"
}

@test "unknown event: exits 0 with no log written" {
  payload=$(jq -n --arg s "$SID" \
    '{hook_event_name:"Notification",session_id:$s}')
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ ! -f "${TMPHOME}/.claude/sessions.log" ]
}
