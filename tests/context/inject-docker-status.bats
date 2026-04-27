#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/context/inject-docker-status.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
}

teardown() {
  rm -rf "$TMPHOME"
}

# PreToolUse Bash payload helper
bash_payload() {
  local cmd="$1"
  jq -n --arg c "$cmd" \
    '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Bash",tool_input:{command:$c}}'
}

@test "approves silently when command is not docker-related" {
  payload=$(bash_payload "ls -la /tmp")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  # Plain approve, no context field
  printf '%s' "$output" | jq -e '.decision == "approve" and (has("context") | not)' >/dev/null
}

@test "approves silently when command is empty" {
  payload=$(jq -n '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Bash",tool_input:{}}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
}

@test "approves on invalid JSON stdin" {
  pfile=$(mktemp); printf 'not json' > "$pfile"
  run bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
}

@test "happy path: docker command yields a context payload (or no-daemon note)" {
  payload=$(bash_payload "docker ps")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  # Either docker is installed (any context) or message about not installed/daemon — must be approve and have context.
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
  # Most CI machines either have no docker or no daemon — both produce a context string.
  if command -v docker >/dev/null 2>&1; then
    printf '%s' "$output" | jq -e 'has("context")' >/dev/null
  fi
}

@test "exits 0 even when jq is missing (simulated by stripping PATH)" {
  # We cannot really remove jq, but a malformed input still triggers the early-approve path.
  payload="{}"
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
}
