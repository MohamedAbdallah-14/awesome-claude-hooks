#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/session/session-name-from-branch.sh"

setup() {
  TMP_REPO=$(mktemp -d)
  (
    cd "$TMP_REPO"
    git init -q
    git config user.email t@t
    git config user.name t
    : > .keep
    git add .keep
    git commit -q -m "init"
  )
}

teardown() {
  rm -rf "$TMP_REPO"
}

start_payload() {
  jq -n --arg c "$TMP_REPO" '{hook_event_name:"SessionStart",cwd:$c}'
}

@test "session-name-from-branch: silent on main" {
  (cd "$TMP_REPO" && git checkout -q -B main)
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-name-from-branch: silent on master" {
  (cd "$TMP_REPO" && git checkout -q -B master)
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-name-from-branch: title-cases feature branch and emits additionalContext" {
  (cd "$TMP_REPO" && git checkout -q -b feature/login-form)
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | startswith("Session: ")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("Feature")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("Login")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("Form")' >/dev/null
}

@test "session-name-from-branch: silent when cwd is not a git repo" {
  NON_GIT=$(mktemp -d)
  payload=$(jq -n --arg c "$NON_GIT" '{hook_event_name:"SessionStart",cwd:$c}')
  run_hook "$HOOK" "$payload"
  rm -rf "$NON_GIT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
