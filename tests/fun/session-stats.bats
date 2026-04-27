#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/fun/session-stats.sh"

@test "session-stats: silent exit when CLAUDE_SHOW_SESSION_STATS=0" {
  payload=$(jq -n '{hook_event_name:"Stop",session_id:"x"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_SHOW_SESSION_STATS=0 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-stats: silent exit when stdout is not a tty (default behaviour)" {
  payload=$(jq -n '{hook_event_name:"Stop",session_id:"x"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-stats: never blocks (exit 0)" {
  payload=$(jq -n '{hook_event_name:"Stop",session_id:"x"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}
