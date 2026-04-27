#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/devops/db-migration-guard.sh"

@test "allows safe SELECT" {
  payload=$(pretool_payload Bash "psql -c 'SELECT * FROM users LIMIT 10'")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows DELETE FROM with WHERE clause" {
  payload=$(pretool_payload Bash "psql -c 'DELETE FROM users WHERE id = 1'")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows non-DB commands" {
  payload=$(pretool_payload Bash "ls -la /tmp")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks DROP TABLE" {
  payload=$(pretool_payload Bash "psql -c 'DROP TABLE users'")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"DROP TABLE"* ]]
}

@test "blocks DROP DATABASE" {
  payload=$(pretool_payload Bash "mysql -e 'DROP DATABASE production'")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"DROP DATABASE"* ]]
}

@test "blocks TRUNCATE TABLE" {
  payload=$(pretool_payload Bash "psql -c 'TRUNCATE TABLE users'")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"TRUNCATE"* ]]
}

@test "blocks DELETE FROM without WHERE" {
  payload=$(pretool_payload Bash "psql -c 'DELETE FROM users'")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"DELETE FROM"* ]]
}

@test "blocks migration rollback" {
  payload=$(pretool_payload Bash "npm run db:rollback")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"rollback"* ]]
}

@test "ignores non-Bash tools" {
  payload=$(pretool_payload Write /tmp/x.sql "DROP TABLE users")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
