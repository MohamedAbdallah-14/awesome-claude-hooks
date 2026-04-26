#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/security/scan-sql-injection.sh"

@test "allows clean Python content (parameterized query)" {
  content='cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))'
  payload=$(pretool_payload Write /tmp/safe.py "$content")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "warn-only: f-string SQL interpolation produces stderr but allows" {
  content='q = f"SELECT * FROM users WHERE id = {user_id}"'
  payload=$(pretool_payload Write /tmp/bad.py "$content")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks f-string SQL interpolation with CLAUDE_SQL_BLOCK=1" {
  content='q = f"SELECT * FROM users WHERE id = {user_id}"'
  payload=$(pretool_payload Write /tmp/bad.py "$content")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env CLAUDE_SQL_BLOCK=1 bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  assert_blocked
  [[ "$output" == *"SQL injection"* ]]
}

@test "blocks JS string-concatenation SQL with CLAUDE_SQL_BLOCK=1" {
  content='const q = "SELECT * FROM users WHERE id = " + userId;'
  payload=$(pretool_payload Write /tmp/bad.js "$content")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env CLAUDE_SQL_BLOCK=1 bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  assert_blocked
}

@test "blocks PHP dot-concat SQL with CLAUDE_SQL_BLOCK=1" {
  content='$q = "SELECT * FROM users WHERE id = " . $id;'
  payload=$(pretool_payload Write /tmp/bad.php "$content")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env CLAUDE_SQL_BLOCK=1 bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  assert_blocked
}

@test "bypass: CLAUDE_SQL_BLOCK=0 (default) lets dangerous content pass" {
  content='q = f"SELECT * FROM users WHERE id = {user_id}"'
  payload=$(pretool_payload Write /tmp/bad.py "$content")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env CLAUDE_SQL_BLOCK=0 bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  assert_allowed
}

@test "ignores non-source-file extension (.txt)" {
  content='q = f"SELECT * FROM users WHERE id = {user_id}"'
  payload=$(pretool_payload Write /tmp/notes.txt "$content")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env CLAUDE_SQL_BLOCK=1 bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  assert_allowed
}

@test "ignores non-Write/Edit/MultiEdit tool" {
  payload=$(jq -n '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:"/tmp/x.py"}}')
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "Edit tool: blocks SQL concatenation in new_string with CLAUDE_SQL_BLOCK=1" {
  content='q = "SELECT * FROM t WHERE x=" + x'
  payload=$(pretool_payload Edit /tmp/bad.py "$content")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env CLAUDE_SQL_BLOCK=1 bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  assert_blocked
}
