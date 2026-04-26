#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/security/audit-bash-commands.sh"

# Build a PostToolUse Bash payload.
posttool_bash_payload() {
  local cmd="$1" exit_code="${2:-0}"
  jq -n --arg cmd "$cmd" --argjson ec "$exit_code" '{
    hook_event_name: "PostToolUse",
    session_id: "test-session-abc",
    tool_name: "Bash",
    tool_input: { command: $cmd },
    tool_response: { exit_code: $ec }
  }'
}

@test "exits 0 and writes a log entry to \$HOME/.claude/bash-audit.log" {
  tmphome=$(mktemp -d)
  payload=$(posttool_bash_payload "ls -la /tmp" 0)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env -i HOME="$tmphome" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ] || { echo "expected exit 0 (got $status). output: $output" >&2; return 1; }
  [ -f "${tmphome}/.claude/bash-audit.log" ]
  grep -q "test-session-abc" "${tmphome}/.claude/bash-audit.log"
  grep -q "ls -la /tmp" "${tmphome}/.claude/bash-audit.log"
  grep -q "| CMD |" "${tmphome}/.claude/bash-audit.log"

  rm -rf "$tmphome"
}

@test "exits 0 and respects CLAUDE_BASH_AUDIT_LOG override" {
  tmpdir=$(mktemp -d)
  custom="${tmpdir}/custom-audit.log"
  payload=$(posttool_bash_payload "echo hello" 0)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env CLAUDE_BASH_AUDIT_LOG="$custom" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "$custom" ]
  grep -q "echo hello" "$custom"

  rm -rf "$tmpdir"
}

@test "exits 0 even when HOME is unset (graceful fallback)" {
  payload=$(posttool_bash_payload "ls" 0)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  # Force log to a writable tmp path so the hook doesn't try to mkdir under
  # a literal "/.claude" at filesystem root when HOME is empty.
  tmplog=$(mktemp -u)
  run env -u HOME CLAUDE_BASH_AUDIT_LOG="$tmplog" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile" "$tmplog"

  [ "$status" -eq 0 ] || { echo "expected exit 0 (got $status). output: $output" >&2; return 1; }
}

@test "exits 0 when command field is empty" {
  payload=$(posttool_bash_payload "" 0)
  tmphome=$(mktemp -d)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$tmphome" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  rm -rf "$tmphome"
}

@test "rotates log file when existing log is over 10 MB" {
  tmphome=$(mktemp -d)
  logdir="${tmphome}/.claude"
  mkdir -p "$logdir"
  logfile="${logdir}/bash-audit.log"

  # Create a sparse file > 10 MB without actually writing 10 MB of data.
  if command -v truncate >/dev/null 2>&1; then
    truncate -s 11M "$logfile"
  else
    # macOS / BSD fallback
    dd if=/dev/zero of="$logfile" bs=1 count=0 seek=11534336 2>/dev/null
  fi

  payload=$(posttool_bash_payload "uname -a" 0)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$tmphome" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  # Old log moved to .1, new log started fresh
  [ -f "${logfile}.1" ]
  [ -f "$logfile" ]
  grep -q "uname -a" "$logfile"

  rm -rf "$tmphome"
}
