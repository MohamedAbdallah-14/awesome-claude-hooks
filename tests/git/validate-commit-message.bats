#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/git/validate-commit-message.sh"

@test "allows conventional feat commit" {
  payload=$(pretool_payload Bash "git commit -m \"feat(auth): add OAuth2 login\"" "")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows fix without scope" {
  payload=$(pretool_payload Bash "git commit -m \"fix: correct null pointer\"" "")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows breaking change marker (!)" {
  payload=$(pretool_payload Bash "git commit -m \"feat(api)!: drop v1 endpoints\"" "")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks non-conventional message" {
  payload=$(pretool_payload Bash "git commit -m \"updated stuff\"" "")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"Conventional Commits"* ]]
}

@test "blocks unknown type" {
  payload=$(pretool_payload Bash "git commit -m \"wip: half-done refactor\"" "")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "blocks missing description after colon" {
  payload=$(pretool_payload Bash "git commit -m \"feat:\"" "")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "skips when --no-edit is used" {
  payload=$(pretool_payload Bash "git commit --amend --no-edit" "")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "skips when no -m flag (editor commit)" {
  payload=$(pretool_payload Bash "git commit" "")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "bypass via CLAUDE_SKIP_COMMIT_VALIDATION=1" {
  payload=$(pretool_payload Bash "git commit -m \"random nonsense message\"" "")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run bash -c "CLAUDE_SKIP_COMMIT_VALIDATION=1 bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "respects CLAUDE_COMMIT_REGEX override" {
  payload=$(pretool_payload Bash "git commit -m \"TICKET-123 do a thing\"" "")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run bash -c "CLAUDE_COMMIT_REGEX='^TICKET-[0-9]+ .+' bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "ignores non-Bash tools" {
  payload=$(pretool_payload Write /tmp/x.txt "git commit -m \"bad message\"")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "ignores non-commit git commands" {
  payload=$(pretool_payload Bash "git status" "")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
