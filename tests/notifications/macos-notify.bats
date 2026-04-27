#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/macos-notify.sh"

# Build a Stop payload.
stop_payload() {
  local sid="${1:-abc12345}"
  jq -n --arg s "$sid" \
    '{hook_event_name:"Stop",session_id:$s,transcript_path:"/tmp/x.jsonl"}'
}

setup() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/osascript.log"
  cat > "${STUB_DIR}/osascript" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$STUB_LOG"
exit 0
EOF
  chmod +x "${STUB_DIR}/osascript"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "macos-notify: invokes osascript with title and body on Darwin" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "macos-notify is a no-op outside Darwin"
  fi
  payload=$(stop_payload "session-abcdefgh")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env STUB_LOG="$STUB_LOG" PATH="${STUB_DIR}:${PATH}" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -f "$STUB_LOG" ]
  grep -q "display notification" "$STUB_LOG"
  grep -q "Claude Code" "$STUB_LOG"
  grep -q "abcdefgh" "$STUB_LOG"
}

@test "macos-notify: passes CLAUDE_NOTIFY_SOUND through to osascript" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "macos-notify is a no-op outside Darwin"
  fi
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env STUB_LOG="$STUB_LOG" PATH="${STUB_DIR}:${PATH}" \
    CLAUDE_NOTIFY_SOUND="Glass" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  grep -q "sound name" "$STUB_LOG"
  grep -q "Glass" "$STUB_LOG"
}

@test "macos-notify: silently exits 0 on non-Darwin systems" {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    skip "non-Darwin path"
  fi
  payload=$(stop_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}

@test "macos-notify: never writes JSON to stdout" {
  payload=$(stop_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || ! echo "$output" | jq -e . >/dev/null 2>&1
}
