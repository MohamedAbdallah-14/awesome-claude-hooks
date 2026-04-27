#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/quality/suggest-fix-on-failure.sh"

failure_payload() {
  local cmd="$1" err="$2"
  jq -n --arg c "$cmd" --arg e "$err" '{
    hook_event_name: "PostToolUseFailure",
    session_id: "test",
    tool_name: "Bash",
    tool_input: {command: $c},
    error: $e,
    is_interrupt: false,
    duration_ms: 200
  }'
}

assert_hint_contains() {
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e \
    --arg needle "$1" \
    '.hookSpecificOutput.hookEventName == "PostToolUseFailure"
     and .hookSpecificOutput.additionalContext != null
     and (.hookSpecificOutput.additionalContext | contains($needle))' \
    >/dev/null
}

@test "suggest-fix-on-failure: hook is executable" {
  [ -x "$HOOK" ]
}

@test "no hint when error is generic" {
  payload=$(failure_payload "true" "exited with code 1")
  run_hook "$HOOK" "$payload"
  assert_allowed
  # Empty stdout — no hint = no JSON.
  [ -z "$output" ]
}

@test "Python ModuleNotFoundError suggests venv/install" {
  payload=$(failure_payload "python script.py" "ModuleNotFoundError: No module named 'requests'")
  run_hook "$HOOK" "$payload"
  assert_hint_contains "requests"
}

@test "node ERR_MODULE_NOT_FOUND suggests npm install" {
  payload=$(failure_payload "node app.js" "Error [ERR_MODULE_NOT_FOUND]: Cannot find module 'lodash'")
  run_hook "$HOOK" "$payload"
  assert_hint_contains "npm install"
}

@test "EADDRINUSE surfaces the port number" {
  payload=$(failure_payload "node server.js" "Error: listen EADDRINUSE: address already in use :::3000")
  run_hook "$HOOK" "$payload"
  assert_hint_contains "3000"
}

@test "command not found surfaces the missing binary" {
  payload=$(failure_payload "uv pip install foo" "bash: uv: command not found")
  run_hook "$HOOK" "$payload"
  assert_hint_contains "uv"
}

@test "lockfile drift recommends install" {
  payload=$(failure_payload "pnpm install --frozen-lockfile" "ERR_PNPM_OUTDATED_LOCKFILE: Cannot install with frozen-lockfile because lockfile is out of sync with package.json")
  run_hook "$HOOK" "$payload"
  assert_hint_contains "lockfile"
}

@test "non-Bash tool: no hint" {
  payload=$(jq -n '{
    hook_event_name: "PostToolUseFailure",
    tool_name: "Write",
    tool_input: {file_path: "/tmp/x"},
    error: "ModuleNotFoundError"
  }')
  run_hook "$HOOK" "$payload"
  assert_allowed
  [ -z "$output" ]
}

@test "bypass via CLAUDE_SUGGEST_FIX_OFF=1" {
  payload=$(failure_payload "python x.py" "ModuleNotFoundError: No module named 'requests'")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_SUGGEST_FIX_OFF=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
