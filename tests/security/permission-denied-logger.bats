#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/security/permission-denied-logger.sh"

setup() {
  TMP_LOG_DIR="$(mktemp -d)"
  export CLAUDE_PERM_DENIED_DIR="$TMP_LOG_DIR"
}

teardown() {
  rm -rf "$TMP_LOG_DIR"
  unset CLAUDE_PERM_DENIED_DIR
}

denied_payload() {
  local tool="$1" cmd="$2" reason="$3"
  jq -n --arg t "$tool" --arg c "$cmd" --arg r "$reason" '{
    hook_event_name: "PermissionDenied",
    session_id: "test",
    tool_name: $t,
    tool_input: {command: $c},
    tool_use_id: "toolu_01TEST",
    denial_reason: $r
  }'
}

@test "permission-denied-logger: hook is executable" {
  [ -x "$HOOK" ]
}

@test "logs a denied Bash call" {
  payload=$(denied_payload Bash "sudo rm /" "Destructive command matched deny rule")
  run_hook "$HOOK" "$payload"
  assert_allowed

  log_file="${TMP_LOG_DIR}/$(date +%Y-%m-%d).jsonl"
  [ -f "$log_file" ]

  jq -e '.tool_name == "Bash"
         and .session_id == "test"
         and (.denial_reason | contains("Destructive"))' \
    < "$log_file" >/dev/null
}

@test "appends multiple denials" {
  run_hook "$HOOK" "$(denied_payload Bash 'a' 'r1')"
  run_hook "$HOOK" "$(denied_payload Write '/etc/passwd' 'r2')"

  log_file="${TMP_LOG_DIR}/$(date +%Y-%m-%d).jsonl"
  count=$(wc -l < "$log_file" | tr -d ' ')
  [ "$count" = "2" ]
}

@test "bypass via CLAUDE_PERM_DENIED_LOG_OFF=1" {
  payload=$(denied_payload Bash "true" "test")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_PERM_DENIED_LOG_OFF=1 \
      CLAUDE_PERM_DENIED_DIR="$TMP_LOG_DIR" \
      bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -f "${TMP_LOG_DIR}/$(date +%Y-%m-%d).jsonl" ]
}

@test "never sets retry / never blocks" {
  payload=$(denied_payload Bash "sudo rm /" "test")
  run_hook "$HOOK" "$payload"
  assert_allowed
  # Hook MUST NOT emit retry:true on its own — that's a separate hook's job.
  [ -z "$output" ] || ! printf '%s' "$output" | jq -e '.hookSpecificOutput.retry == true' >/dev/null
}
