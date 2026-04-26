#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/quality/validate-json-yaml.sh"

@test "allows valid JSON" {
  payload=$(pretool_payload Write /tmp/x.json '{"a":1}')
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks invalid JSON" {
  payload=$(pretool_payload Write /tmp/x.json '{"a": 1,}')
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "allows valid YAML" {
  payload=$(pretool_payload Write /tmp/x.yml $'a: 1\nb: two\n')
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks invalid YAML" {
  # Tab indentation under a mapping is a YAML error.
  payload=$(pretool_payload Write /tmp/x.yaml $'a:\n\tb: 1')
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "ignores non-json/yaml files" {
  payload=$(pretool_payload Write /tmp/x.py "print('ok')")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
