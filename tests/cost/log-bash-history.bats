#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/cost/log-bash-history.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
}

teardown() {
  rm -rf "$TMPHOME"
}

bash_post_payload() {
  local cmd="$1" stderr="${2:-}"
  jq -n --arg c "$cmd" --arg e "$stderr" \
    '{hook_event_name:"PostToolUse",session_id:"sess-abc",tool_name:"Bash",
      tool_input:{command:$c},tool_response:{stdout:"",stderr:$e}}'
}

@test "happy path: appends entry to \$HOME/.claude/bash-history.log" {
  payload=$(bash_post_payload "ls -la /tmp")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  log="${TMPHOME}/.claude/bash-history.log"
  [ -f "$log" ]
  grep -q "sess-abc" "$log"
  grep -q "ls -la /tmp" "$log"
  grep -qE '\| 0$' "$log"
}

@test "exit code marker: stderr presence flags ERR" {
  payload=$(bash_post_payload "false" "boom")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  grep -qE '\| ERR$' "${TMPHOME}/.claude/bash-history.log"
}

@test "silent skip: empty command produces no log line, exits 0" {
  payload=$(bash_post_payload "")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  log="${TMPHOME}/.claude/bash-history.log"
  if [[ -f "$log" ]]; then
    [ ! -s "$log" ]
  fi
}

@test "respects CLAUDE_BASH_HISTORY_LOG override" {
  custom="${TMPHOME}/custom-history.log"
  payload=$(bash_post_payload "echo hi")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_BASH_HISTORY_LOG="$custom" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -f "$custom" ]
  grep -q "echo hi" "$custom"
}

@test "sanitizes pipe characters in command (no log column splits)" {
  payload=$(bash_post_payload "ls | grep foo")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  # The pipe in the command must have been transformed (the hook uses '/' as
  # the substitute), so the line still has exactly 4 fields.
  log="${TMPHOME}/.claude/bash-history.log"
  line=$(tail -1 "$log")
  field_count=$(printf '%s' "$line" | awk -F' \\| ' '{print NF}')
  [ "$field_count" -eq 4 ]
}
