#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/prompt/rate-limiter.sh"

setup() {
  SID="ratelimit-$(date +%s)-$RANDOM"
  COUNT_FILE="/tmp/claude-rate-${SID}.txt"
  TS_FILE="/tmp/claude-rate-${SID}.ts"
  rm -f "$COUNT_FILE" "$TS_FILE"
}

teardown() {
  rm -f "$COUNT_FILE" "$TS_FILE"
}

call_with_session() {
  local sid="$1"
  jq -n --arg s "$sid" \
    '{hook_event_name:"PreToolUse",session_id:$s,tool_name:"Bash",tool_input:{command:"echo"}}'
}

@test "rate-limiter: first call is silent and initializes counter file" {
  payload=$(call_with_session "$SID")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$COUNT_FILE" ]
  [ -f "$TS_FILE" ]
  [ "$(cat "$COUNT_FILE")" = "1" ]
}

@test "rate-limiter: stays silent under the threshold" {
  payload=$(call_with_session "$SID")
  for _ in $(seq 1 10); do
    run_hook "$HOOK" "$payload"
    [ "$status" -eq 0 ]
  done
  [ -z "$output" ]
}

@test "rate-limiter: emits additionalContext warning above 50 calls in window" {
  payload=$(call_with_session "$SID")
  # Pre-seed counter to just under threshold so we don't have to call 51 times
  echo "$(date +%s)" > "$TS_FILE"
  echo "50" > "$COUNT_FILE"
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("High tool call rate")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("loop")' >/dev/null
}

@test "rate-limiter: rolls over after window expires" {
  payload=$(call_with_session "$SID")
  # Pretend window started 2 minutes ago, with high count — expect reset, no warning
  echo "$(( $(date +%s) - 120 ))" > "$TS_FILE"
  echo "999" > "$COUNT_FILE"
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$COUNT_FILE")" = "1" ]
}

@test "rate-limiter: sanitises session id for filename safety" {
  # Session id with path-traversal chars must not break things
  payload=$(call_with_session 'foo/../bar; rm -rf')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  # Sanitisation must collapse traversal segments — no resolved file at
  # /tmp/bar should ever appear as a side effect.
  [ ! -e /tmp/bar ]
  [ ! -e /tmp/bar.txt ]
  # And a sanitised rate file should exist under the expected namespace.
  ls /tmp/claude-rate-*.txt >/dev/null 2>&1 || ls /tmp/claude-rate-*.ts >/dev/null 2>&1
  # Cleanup any rate file the hook may have made under sanitised name
  rm -f /tmp/claude-rate-foo*.txt /tmp/claude-rate-foo*.ts
  rm -f /tmp/claude-rate-bar*.txt /tmp/claude-rate-bar*.ts
}
