#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/session/precompact-backup.sh"

setup() {
  TMP_HOME=$(mktemp -d)
  TRANSCRIPT=$(mktemp)
  printf '{"role":"user","content":"hi"}\n' > "$TRANSCRIPT"
}

teardown() {
  rm -rf "$TMP_HOME"
  rm -f "$TRANSCRIPT"
}

@test "precompact-backup: copies transcript to ~/.claude/compacted with timestamp" {
  payload=$(jq -n --arg t "$TRANSCRIPT" '{hook_event_name:"PreCompact",transcript_path:$t}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -d "${TMP_HOME}/.claude/compacted" ]
  # Exactly one backup file should exist
  count=$(find "${TMP_HOME}/.claude/compacted" -type f -name "*.json" | wc -l | xargs)
  [ "$count" -ge 1 ]
}

@test "precompact-backup: silent when transcript_path is empty" {
  payload=$(jq -n '{hook_event_name:"PreCompact"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "precompact-backup: silent when transcript file does not exist" {
  payload=$(jq -n '{hook_event_name:"PreCompact",transcript_path:"/no/such/file.jsonl"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "precompact-backup: never writes JSON to stdout" {
  payload=$(jq -n --arg t "$TRANSCRIPT" '{hook_event_name:"PreCompact",transcript_path:$t}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
