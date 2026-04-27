#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/session/context-threshold-guard.sh"

@test "context-threshold-guard: silent when transcript missing" {
  payload=$(jq -n '{hook_event_name:"UserPromptSubmit",transcript_path:"/no/such/file"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "context-threshold-guard: silent when transcript under threshold" {
  T=$(mktemp)
  yes "line" | head -100 > "$T"
  payload=$(jq -n --arg t "$T" '{hook_event_name:"UserPromptSubmit",transcript_path:$t}')
  run_hook "$HOOK" "$payload"
  rm -f "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "context-threshold-guard: emits additionalContext when transcript exceeds threshold" {
  T=$(mktemp)
  yes "line" | head -2500 > "$T"
  payload=$(jq -n --arg t "$T" '{hook_event_name:"UserPromptSubmit",transcript_path:$t}')
  run_hook "$HOOK" "$payload"
  rm -f "$T"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("Context is large")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("/compact")' >/dev/null
}

@test "context-threshold-guard: silent when transcript_path field is empty" {
  payload=$(jq -n '{hook_event_name:"UserPromptSubmit"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
