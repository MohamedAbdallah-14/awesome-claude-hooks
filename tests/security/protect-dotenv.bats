#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/security/protect-dotenv.sh"

@test "blocks Write to .env" {
  payload=$(pretool_payload Write /home/me/proj/.env "FOO=bar")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 2 ]
}

@test "blocks Write to .env.production" {
  payload=$(pretool_payload Write /tmp/.env.production "FOO=bar")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 2 ]
}

@test "blocks Edit on .env.local" {
  payload=$(pretool_payload Edit /tmp/.env.local "FOO=bar")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 2 ]
}

@test "blocks path ending in .env" {
  payload=$(pretool_payload Write /tmp/config/database.env "DB=x")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 2 ]
}

@test "allows .env.example" {
  payload=$(pretool_payload Write /tmp/.env.example "FOO=placeholder")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}

@test "allows regular .py file" {
  payload=$(pretool_payload Write /tmp/main.py "print('hi')")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}

@test "bypass via CLAUDE_ALLOW_ENV_WRITES=1" {
  payload=$(pretool_payload Write /tmp/.env "FOO=bar")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_ALLOW_ENV_WRITES=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}
