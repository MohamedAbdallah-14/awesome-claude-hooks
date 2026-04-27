#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/session/session-end-summary.sh"

setup() {
  TMP_SESS_DIR="$(mktemp -d)"
  export CLAUDE_SESSIONS_DIR="$TMP_SESS_DIR"
}

teardown() {
  rm -rf "$TMP_SESS_DIR"
  unset CLAUDE_SESSIONS_DIR
}

session_end_payload() {
  local reason="$1" transcript="${2:-}"
  jq -n --arg r "$reason" --arg t "$transcript" '{
    hook_event_name: "SessionEnd",
    session_id: "sess_abc123",
    cwd: "/tmp/test-cwd",
    reason: $r,
    transcript_path: $t
  }'
}

@test "session-end-summary: hook is executable" {
  [ -x "$HOOK" ]
}

@test "writes a digest with reason and session id" {
  payload=$(session_end_payload "logout" "")
  run_hook "$HOOK" "$payload"
  assert_allowed

  log_file="${TMP_SESS_DIR}/$(date +%Y-%m-%d).md"
  [ -f "$log_file" ]

  grep -q 'reason: `logout`' "$log_file"
  grep -q 'sess_abc123' "$log_file"
  grep -q '/tmp/test-cwd' "$log_file"
}

@test "counts tool calls from transcript" {
  transcript=$(mktemp)
  cat > "$transcript" <<'EOF'
{"type":"tool_use","name":"Write","timestamp":"2026-04-26T10:00:00Z"}
{"type":"tool_use","name":"Edit"}
{"type":"tool_use","name":"Bash"}
{"type":"tool_use","name":"Bash"}
{"type":"tool_use","name":"Read"}
EOF

  payload=$(session_end_payload "clear" "$transcript")
  run_hook "$HOOK" "$payload"
  assert_allowed

  log_file="${TMP_SESS_DIR}/$(date +%Y-%m-%d).md"
  grep -q 'tool calls: 5' "$log_file"
  grep -q 'Write 1' "$log_file"
  grep -q 'Bash 2' "$log_file"

  rm -f "$transcript"
}

@test "appends across multiple session ends" {
  run_hook "$HOOK" "$(session_end_payload 'logout' '')"
  run_hook "$HOOK" "$(session_end_payload 'clear' '')"

  log_file="${TMP_SESS_DIR}/$(date +%Y-%m-%d).md"
  count=$(grep -c '^### Session ended' "$log_file")
  [ "$count" = "2" ]
}

@test "bypass via CLAUDE_SESSION_END_SUMMARY_OFF=1" {
  payload=$(session_end_payload "logout" "")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_SESSION_END_SUMMARY_OFF=1 \
      CLAUDE_SESSIONS_DIR="$TMP_SESS_DIR" \
      bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -f "${TMP_SESS_DIR}/$(date +%Y-%m-%d).md" ]
}

@test "missing transcript: still writes digest, counts default to 0" {
  payload=$(session_end_payload "other" "/nonexistent/transcript.jsonl")
  run_hook "$HOOK" "$payload"
  assert_allowed

  log_file="${TMP_SESS_DIR}/$(date +%Y-%m-%d).md"
  grep -q 'tool calls: 0' "$log_file"
}
