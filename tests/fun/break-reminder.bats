#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/fun/break-reminder.sh"

setup() {
  TMP_HOME=$(mktemp -d)
  mkdir -p "${TMP_HOME}/.claude"
  REMINDED_FILE="/tmp/claude-break-reminded.time"
  # Make sure there's no stale reminder from earlier tests on this box
  rm -f "$REMINDED_FILE"
}

teardown() {
  rm -rf "$TMP_HOME"
  rm -f "$REMINDED_FILE"
}

@test "break-reminder: silent when no sessions log exists" {
  payload=$(jq -n '{hook_event_name:"Stop"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "break-reminder: silent when total time below threshold" {
  TODAY=$(date -u +"%Y-%m-%d")
  printf '%s|sess1|60|0\n' "$TODAY" > "${TMP_HOME}/.claude/sessions.log"
  payload=$(jq -n '{hook_event_name:"Stop"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "break-reminder: rate-limited via existing reminder file" {
  TODAY=$(date -u +"%Y-%m-%d")
  printf '%s|sess1|999999|0\n' "$TODAY" > "${TMP_HOME}/.claude/sessions.log"
  # Mark "reminded just now"
  date +%s > "$REMINDED_FILE"
  payload=$(jq -n '{hook_event_name:"Stop"}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "break-reminder: never blocks (exit 0)" {
  payload=$(jq -n '{hook_event_name:"Stop"}')
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK'" <<< "$payload"
  [ "$status" -eq 0 ]
}
