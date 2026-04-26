#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/security/block-system-paths.sh"

@test "blocks Write to /etc/hosts" {
  payload=$(pretool_payload Write /etc/hosts "127.0.0.1 evil")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 2 ]
}

@test "blocks Write to /usr/bin/foo" {
  payload=$(pretool_payload Write /usr/bin/foo "x")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 2 ]
}

@test "allows Write to /tmp/foo" {
  payload=$(pretool_payload Write /tmp/foo "x")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}

@test "allows Write to home directory" {
  payload=$(pretool_payload Write "$HOME/code/file.txt" "x")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}

@test "blocks bash redirect into /etc" {
  payload=$(pretool_payload Bash "echo bad > /etc/hosts")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 2 ]
}

@test "blocks chmod 777 /" {
  payload=$(pretool_payload Bash "chmod 777 /")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 2 ]
}

@test "allowlist permits explicitly approved path" {
  payload=$(pretool_payload Write /etc/hosts "127.0.0.1 ok")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_ALLOWED_SYSTEM_PATHS=/etc/hosts bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}
