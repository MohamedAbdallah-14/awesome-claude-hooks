#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/security/audit-file-writes.sh"

# Build a PostToolUse Write payload.
posttool_write_payload() {
  local path="$1" content="${2:-}"
  jq -n --arg p "$path" --arg c "$content" '{
    hook_event_name: "PostToolUse",
    session_id: "test-session-xyz",
    tool_name: "Write",
    tool_input: { file_path: $p, content: $c }
  }'
}

@test "exits 0 and writes a log entry to \$HOME/.claude/audit.log" {
  tmphome=$(mktemp -d)
  target="${tmphome}/some-file.txt"
  printf 'hello world\n' > "$target"

  payload=$(posttool_write_payload "$target" "hello world")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env -i HOME="$tmphome" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ] || { echo "expected exit 0 (got $status). output: $output" >&2; return 1; }
  [ -f "${tmphome}/.claude/audit.log" ]
  grep -q "test-session-xyz" "${tmphome}/.claude/audit.log"
  grep -q "| WRITE |" "${tmphome}/.claude/audit.log"
  grep -q "$target" "${tmphome}/.claude/audit.log"

  rm -rf "$tmphome"
}

@test "exits 0 and respects CLAUDE_AUDIT_LOG override" {
  tmpdir=$(mktemp -d)
  custom="${tmpdir}/custom.log"
  payload=$(posttool_write_payload "/tmp/x.ts" "const a = 1;")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env CLAUDE_AUDIT_LOG="$custom" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "$custom" ]
  grep -q "/tmp/x.ts" "$custom"

  rm -rf "$tmpdir"
}

@test "exits 0 even when HOME is unset (graceful fallback)" {
  payload=$(posttool_write_payload "/tmp/whatever.txt" "x")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  tmplog=$(mktemp -u)
  run env -u HOME CLAUDE_AUDIT_LOG="$tmplog" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile" "$tmplog"

  [ "$status" -eq 0 ] || { echo "expected exit 0 (got $status). output: $output" >&2; return 1; }
}

@test "exits 0 when file_path is empty" {
  payload=$(jq -n '{
    hook_event_name: "PostToolUse",
    session_id: "s",
    tool_name: "Write",
    tool_input: { file_path: "", content: "x" }
  }')
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
  logfile="${logdir}/audit.log"

  if command -v truncate >/dev/null 2>&1; then
    truncate -s 11M "$logfile"
  else
    dd if=/dev/zero of="$logfile" bs=1 count=0 seek=11534336 2>/dev/null
  fi

  target="${tmphome}/file.md"
  printf 'data' > "$target"
  payload=$(posttool_write_payload "$target" "data")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$tmphome" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "${logfile}.1" ]
  [ -f "$logfile" ]
  grep -q "$target" "$logfile"

  rm -rf "$tmphome"
}
