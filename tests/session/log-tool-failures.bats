#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/session/log-tool-failures.sh"

setup() {
  TMP_LOG_DIR="$(mktemp -d)"
  export CLAUDE_TOOL_FAILURES_DIR="$TMP_LOG_DIR"
}

teardown() {
  rm -rf "$TMP_LOG_DIR"
  unset CLAUDE_TOOL_FAILURES_DIR
}

failure_payload() {
  local tool="$1" cmd="$2" err="$3"
  jq -n --arg t "$tool" --arg c "$cmd" --arg e "$err" '{
    hook_event_name: "PostToolUseFailure",
    session_id: "test-session",
    tool_name: $t,
    tool_input: {command: $c},
    tool_use_id: "toolu_01TEST",
    error: $e,
    is_interrupt: false,
    duration_ms: 1234
  }'
}

@test "log-tool-failures: hook is executable" {
  [ -x "$HOOK" ]
}

@test "log-tool-failures: writes a JSONL line for a failed Bash call" {
  payload=$(failure_payload Bash "npm test" "exit 1: 3 tests failed")
  run_hook "$HOOK" "$payload"
  assert_allowed

  log_file="${TMP_LOG_DIR}/$(date +%Y-%m-%d).jsonl"
  [ -f "$log_file" ]

  # Exactly one line, valid JSON, with the expected fields.
  line_count=$(wc -l < "$log_file" | tr -d ' ')
  [ "$line_count" = "1" ]

  jq -e '.tool_name == "Bash" and .session_id == "test-session" and (.error | contains("3 tests failed"))' \
    < "$log_file" >/dev/null
}

@test "log-tool-failures: appends, doesn't truncate" {
  run_hook "$HOOK" "$(failure_payload Bash 'a' 'err1')"
  run_hook "$HOOK" "$(failure_payload Bash 'b' 'err2')"

  log_file="${TMP_LOG_DIR}/$(date +%Y-%m-%d).jsonl"
  line_count=$(wc -l < "$log_file" | tr -d ' ')
  [ "$line_count" = "2" ]
}

@test "log-tool-failures: bypass via CLAUDE_LOG_TOOL_FAILURES_OFF=1" {
  payload=$(failure_payload Bash "npm test" "fail")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_LOG_TOOL_FAILURES_OFF=1 \
      CLAUDE_TOOL_FAILURES_DIR="$TMP_LOG_DIR" \
      bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -f "${TMP_LOG_DIR}/$(date +%Y-%m-%d).jsonl" ]
}

@test "log-tool-failures: truncates absurdly long error fields" {
  big=$(printf 'x%.0s' {1..5000})
  payload=$(failure_payload Bash "true" "$big")
  run_hook "$HOOK" "$payload"
  assert_allowed

  log_file="${TMP_LOG_DIR}/$(date +%Y-%m-%d).jsonl"
  err_len=$(jq -r '.error | length' < "$log_file")
  [ "$err_len" -le 2048 ]
}
