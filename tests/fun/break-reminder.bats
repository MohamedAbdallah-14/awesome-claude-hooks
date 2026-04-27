#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/fun/break-reminder.sh"

setup() {
  TMP_HOME=$(mktemp -d)
  mkdir -p "${TMP_HOME}/.claude"
  # Per-test marker keeps parallel bats workers (`bats --jobs N`) from
  # racing on /tmp. The hook honours CLAUDE_BREAK_REMINDER_FILE.
  REMINDED_FILE="${TMP_HOME}/claude-break-reminded.time"
  export CLAUDE_BREAK_REMINDER_FILE="$REMINDED_FILE"
  rm -f "$REMINDED_FILE"
  # Stub osascript / notify-send so the hook doesn't fire real desktop
  # notifications during tests (this was leaking into the maintainer's
  # macOS Notification Center).
  STUB_DIR=$(mktemp -d)
  for bin in osascript notify-send; do
    cat > "${STUB_DIR}/${bin}" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${STUB_DIR}/${bin}"
  done
  export PATH="${STUB_DIR}:${PATH}"
}

teardown() {
  rm -rf "$TMP_HOME" "$STUB_DIR"
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
