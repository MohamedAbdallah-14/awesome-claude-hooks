#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/devops/infra-audit-log.sh"

# Build a PostToolUse Bash payload (this hook is PostToolUse, log-only).
posttool_bash_payload() {
  local cmd="$1"
  jq -n --arg cmd "$cmd" \
    '{hook_event_name:"PostToolUse",session_id:"test",tool_name:"Bash",tool_input:{command:$cmd}}'
}

setup() {
  TEST_HOME=$(mktemp -d)
  export HOME="$TEST_HOME"
}

teardown() {
  if [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" ]]; then
    rm -rf "$TEST_HOME"
  fi
}

run_with_home() {
  local payload="$1"
  local tmp
  tmp=$(mktemp)
  printf '%s' "$payload" > "$tmp"
  run env HOME="$TEST_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
}

@test "logs terraform commands and exits 0" {
  payload=$(posttool_bash_payload "terraform apply -auto-approve")
  run_with_home "$payload"
  [ "$status" -eq 0 ]
  [ -f "${TEST_HOME}/.claude/infra-audit.log" ]
  grep -q "terraform apply" "${TEST_HOME}/.claude/infra-audit.log"
}

@test "logs kubectl commands" {
  payload=$(posttool_bash_payload "kubectl get pods")
  run_with_home "$payload"
  [ "$status" -eq 0 ]
  grep -q "kubectl get pods" "${TEST_HOME}/.claude/infra-audit.log"
}

@test "logs aws commands" {
  payload=$(posttool_bash_payload "aws s3 ls")
  run_with_home "$payload"
  [ "$status" -eq 0 ]
  grep -q "aws s3 ls" "${TEST_HOME}/.claude/infra-audit.log"
}

@test "logs docker commands" {
  payload=$(posttool_bash_payload "docker ps")
  run_with_home "$payload"
  [ "$status" -eq 0 ]
  grep -q "docker ps" "${TEST_HOME}/.claude/infra-audit.log"
}

@test "silently ignores non-infra commands" {
  payload=$(posttool_bash_payload "ls -la /tmp")
  run_with_home "$payload"
  [ "$status" -eq 0 ]
  # Log file should not exist or should not contain this command
  if [ -f "${TEST_HOME}/.claude/infra-audit.log" ]; then
    ! grep -q "ls -la /tmp" "${TEST_HOME}/.claude/infra-audit.log"
  fi
}

@test "never blocks (exits 0) even on infra commands" {
  payload=$(posttool_bash_payload "terraform destroy")
  run_with_home "$payload"
  [ "$status" -eq 0 ]
  # Should produce no decision JSON on stdout
  [ -z "$output" ] || ! printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1
}

@test "appends multiple entries" {
  payload1=$(posttool_bash_payload "terraform plan")
  run_with_home "$payload1"
  payload2=$(posttool_bash_payload "kubectl get nodes")
  run_with_home "$payload2"
  [ "$(wc -l < "${TEST_HOME}/.claude/infra-audit.log" | tr -d ' ')" -ge 2 ]
}

@test "ignores empty command" {
  payload=$(jq -n '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{}}')
  run_with_home "$payload"
  [ "$status" -eq 0 ]
}
