#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/fun/motivational-quote.sh"

@test "motivational-quote: silent exit when CLAUDE_MOTIVATIONAL=0" {
  payload=$(jq -n '{hook_event_name:"Stop"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_MOTIVATIONAL=0 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "motivational-quote: silent exit when stdout is not a tty (default)" {
  payload=$(jq -n '{hook_event_name:"Stop"}')
  run_hook "$HOOK" "$payload"
  # bats redirects stdout, so the tty check will skip
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "motivational-quote: never blocks (exit 0)" {
  payload=$(jq -n '{hook_event_name:"Stop"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}
