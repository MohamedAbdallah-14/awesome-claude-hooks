#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/prompt/no-ask-human-blocker.sh"

prompt_payload() {
  local prompt="$1"
  jq -n --arg p "$prompt" '{hook_event_name:"UserPromptSubmit",session_id:"s",prompt:$p}'
}

@test "no-ask-human-blocker: silent when no trigger phrase present" {
  payload=$(prompt_payload "please refactor the auth module")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-ask-human-blocker: appends reinforcement when prompt contains 'just do it'" {
  payload=$(prompt_payload "just do it without confirming")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | contains("Proceed autonomously")' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | startswith("just do it")' >/dev/null
}

@test "no-ask-human-blocker: triggers on 'don't ask'" {
  payload=$(prompt_payload "Refactor and don't ask me anything")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | contains("Proceed autonomously")' >/dev/null
}

@test "no-ask-human-blocker: triggers on 'autonomously'" {
  payload=$(prompt_payload "do it autonomously")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | contains("Proceed autonomously")' >/dev/null
}

@test "no-ask-human-blocker: case-insensitive trigger detection" {
  payload=$(prompt_payload "JUST DO IT")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt' >/dev/null
}

@test "no-ask-human-blocker: silent on empty prompt" {
  payload=$(jq -n '{hook_event_name:"UserPromptSubmit",prompt:""}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
