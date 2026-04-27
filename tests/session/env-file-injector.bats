#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/session/env-file-injector.sh"

setup() {
  TMP_CWD=$(mktemp -d)
}

teardown() {
  rm -rf "$TMP_CWD"
}

start_payload() {
  jq -n --arg c "$TMP_CWD" '{hook_event_name:"SessionStart",cwd:$c}'
}

@test "env-file-injector: silent when .claude.env does not exist" {
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "env-file-injector: emits additionalContext with key=value pairs" {
  printf 'PROJECT=demo\nMODE=dev\n' > "${TMP_CWD}/.claude.env"
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("PROJECT=demo")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("MODE=dev")' >/dev/null
}

@test "env-file-injector: redacts likely-secret values" {
  printf 'OPENAI_KEY=sk-abc123def\nNORMAL=ok\n' > "${TMP_CWD}/.claude.env"
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("redacted")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("sk-abc123def") | not' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("NORMAL=ok")' >/dev/null
}

@test "env-file-injector: skips comments and blank lines" {
  printf '# a comment\n\nFOO=bar\n' > "${TMP_CWD}/.claude.env"
  payload=$(start_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.additionalContext | contains("FOO=bar")' >/dev/null
  echo "$output" | jq -e '.additionalContext | contains("a comment") | not' >/dev/null
}
