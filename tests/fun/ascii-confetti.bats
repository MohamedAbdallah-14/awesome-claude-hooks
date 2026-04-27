#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/fun/ascii-confetti.sh"

@test "ascii-confetti: silent exit when CLAUDE_CONFETTI is unset (opt-in)" {
  payload=$(jq -n '{hook_event_name:"Stop"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ascii-confetti: silent exit when stdout is not a tty even with CLAUDE_CONFETTI=1" {
  payload=$(jq -n '{hook_event_name:"Stop"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  # bats captures stdout via pipe — not a tty — so the tty check trips and we exit silent
  run env CLAUDE_CONFETTI=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ascii-confetti: never blocks (exit 0)" {
  payload=$(jq -n '{hook_event_name:"Stop"}')
  run env CLAUDE_CONFETTI=0 bash -c "bash '$HOOK'" <<< "$payload"
  [ "$status" -eq 0 ]
}
