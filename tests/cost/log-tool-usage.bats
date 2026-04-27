#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/cost/log-tool-usage.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
}

teardown() {
  rm -rf "$TMPHOME"
}

write_payload() {
  local fp="$1"
  jq -n --arg p "$fp" \
    '{hook_event_name:"PostToolUse",session_id:"sess-1",tool_name:"Write",tool_input:{file_path:$p}}'
}

bash_payload() {
  local cmd="$1"
  jq -n --arg c "$cmd" \
    '{hook_event_name:"PostToolUse",session_id:"sess-1",tool_name:"Bash",tool_input:{command:$c}}'
}

@test "happy path: writes CSV header and row for Write tool" {
  payload=$(write_payload "/tmp/foo.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  log="${TMPHOME}/.claude/usage.csv"
  [ -f "$log" ]
  head -1 "$log" | grep -q '^timestamp,session_id,tool_name,context$'
  tail -1 "$log" | grep -q '"Write"'
  tail -1 "$log" | grep -q '"/tmp/foo.txt"'
}

@test "Bash payload is recorded with command in context column" {
  payload=$(bash_payload "echo hello world")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  tail -1 "${TMPHOME}/.claude/usage.csv" | grep -q '"Bash"'
  tail -1 "${TMPHOME}/.claude/usage.csv" | grep -q "echo hello world"
}

@test "respects CLAUDE_USAGE_LOG override" {
  custom="${TMPHOME}/usage-custom.csv"
  payload=$(write_payload "/tmp/x.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_USAGE_LOG="$custom" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "$custom" ]
  [ ! -f "${TMPHOME}/.claude/usage.csv" ]
}

@test "rotates log when existing file exceeds 5 MB" {
  custom="${TMPHOME}/usage.csv"
  if command -v truncate >/dev/null 2>&1; then
    truncate -s 6M "$custom"
  else
    dd if=/dev/zero of="$custom" bs=1 count=0 seek=6291456 2>/dev/null
  fi

  payload=$(write_payload "/tmp/x.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_USAGE_LOG="$custom" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "${custom}.1" ]
  [ -f "$custom" ]
  head -1 "$custom" | grep -q "^timestamp,"
}

@test "tool with neither file_path nor command leaves context empty" {
  payload=$(jq -n '{hook_event_name:"PostToolUse",session_id:"sess-1",tool_name:"Glob",tool_input:{pattern:"*"}}')
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  tail -1 "${TMPHOME}/.claude/usage.csv" | grep -qE '"Glob",""$'
}
