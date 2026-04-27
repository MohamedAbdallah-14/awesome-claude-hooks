#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/devops/docker-prod-guard.sh"

@test "allows docker ps" {
  payload=$(pretool_payload Bash "docker ps")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows docker logs on prod container (readonly)" {
  payload=$(pretool_payload Bash "docker logs my-prod-api")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows docker rm on dev container" {
  payload=$(pretool_payload Bash "docker rm dev-container")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows non-docker commands" {
  payload=$(pretool_payload Bash "echo docker prod stuff")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks docker rm prod container" {
  payload=$(pretool_payload Bash "docker rm my-prod-api")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"production"* ]]
}

@test "blocks docker stop production container" {
  payload=$(pretool_payload Bash "docker stop production-db")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "blocks docker kill on live container" {
  payload=$(pretool_payload Bash "docker kill api-live")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "blocks docker volume rm prod" {
  payload=$(pretool_payload Bash "docker volume rm prod-data")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "bypass via CLAUDE_ALLOW_DOCKER_PROD=1" {
  payload=$(pretool_payload Bash "docker rm my-prod-api")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_ALLOW_DOCKER_PROD=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "ignores non-Bash tools" {
  payload=$(pretool_payload Write /tmp/x.sh "docker rm prod-api")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
