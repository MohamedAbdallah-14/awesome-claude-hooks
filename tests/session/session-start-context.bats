#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/session/session-start-context.sh"

setup() {
  TMP_REPO=$(mktemp -d)
  (
    cd "$TMP_REPO"
    git init -q
    git config user.email t@t
    git config user.name t
    : > .keep
    git add .keep
    git commit -q -m "first"
    : > another
    git add another
    git commit -q -m "second"
  )
}

teardown() {
  rm -rf "$TMP_REPO"
}

start_payload() {
  jq -n --arg c "$TMP_REPO" '{hook_event_name:"SessionStart",cwd:$c}'
}

@test "session-start-context: emits Directory in context for any cwd" {
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("Directory:")' >/dev/null
}

@test "session-start-context: includes branch and recent commits when in a git repo" {
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("Branch:")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("Recent commits")' >/dev/null
}

@test "session-start-context: includes TODO.md when present" {
  printf '## todo\n- finish auth\n' > "${TMP_REPO}/TODO.md"
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("TODO.md")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("finish auth")' >/dev/null
}

@test "session-start-context: works without git (only Directory line)" {
  NON_GIT=$(mktemp -d)
  payload=$(jq -n --arg c "$NON_GIT" '{hook_event_name:"SessionStart",cwd:$c}')
  run_hook "$HOOK" "$payload"
  rm -rf "$NON_GIT"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("Directory:")' >/dev/null
}
