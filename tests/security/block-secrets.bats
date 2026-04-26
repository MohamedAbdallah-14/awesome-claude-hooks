#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/security/block-secrets.sh"

@test "allows clean content" {
  payload=$(pretool_payload Write /tmp/foo.txt "hello world")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks OpenAI API key" {
  fake_key="sk-$(printf 'a%.0s' {1..48})"
  payload=$(pretool_payload Write /tmp/foo.py "API_KEY = '${fake_key}'")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"OpenAI API key"* ]]
}

@test "blocks AWS access key id" {
  payload=$(pretool_payload Write /tmp/foo.tf "key = 'AKIAIOSFODNN7EXAMPLE'")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"AWS"* ]]
}

@test "blocks GitHub personal access token" {
  fake="ghp_$(printf 'a%.0s' {1..36})"
  payload=$(pretool_payload Write /tmp/foo.sh "TOKEN=${fake}")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"GitHub"* ]]
}

@test "blocks password assignment" {
  payload=$(pretool_payload Write /tmp/foo.py 'password = "hunter22extra"')
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"password"* ]]
}

@test "bypass via CLAUDE_ALLOW_SECRETS=1" {
  fake_key="sk-$(printf 'a%.0s' {1..48})"
  payload=$(pretool_payload Write /tmp/foo.py "k='${fake_key}'")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_ALLOW_SECRETS=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "ignores non-Write/Edit tools" {
  payload=$(jq -n '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:"/x"}}')
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "Edit tool: blocks secret in new_string" {
  fake_key="sk-$(printf 'b%.0s' {1..48})"
  payload=$(pretool_payload Edit /tmp/x.py "k='${fake_key}'")
  run_hook "$HOOK" "$payload"
  assert_blocked
}
