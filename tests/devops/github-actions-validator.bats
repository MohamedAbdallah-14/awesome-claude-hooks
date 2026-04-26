#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/devops/github-actions-validator.sh"

# Helper: build a Write payload that uses tool_input.path (this hook's
# expected key) and tool_input.content. The shared pretool_payload Write
# emits file_path, so we construct it manually.
gh_workflow_payload() {
  local path="$1" content="$2"
  jq -n --arg p "$path" --arg c "$content" \
    '{hook_event_name:"PreToolUse",session_id:"test",tool_name:"Write",tool_input:{path:$p,content:$c}}'
}

@test "allows valid workflow YAML" {
  content='name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
'
  payload=$(gh_workflow_payload ".github/workflows/ci.yml" "$content")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "ignores files outside .github/workflows/" {
  payload=$(gh_workflow_payload "src/app.yml" "this: is: not: valid: yaml: at: all:")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks invalid workflow YAML" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 not available"
  fi
  if ! python3 -c "import yaml" 2>/dev/null; then
    skip "PyYAML not installed"
  fi
  # Unclosed bracket / mapping value error
  content='name: CI
on: [push
jobs:
  build:
    runs-on: ubuntu-latest
'
  payload=$(gh_workflow_payload ".github/workflows/ci.yml" "$content")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"YAML"* || "$output" == *"yaml"* ]]
}

@test "ignores non-Write tools" {
  payload=$(pretool_payload Bash "echo invalid: yaml: [unclosed")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "ignores Write to .yaml outside workflows dir" {
  payload=$(gh_workflow_payload "config/app.yaml" "key: value")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
