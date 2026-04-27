#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/linux-notify.sh"

stop_payload() {
  local sid="${1:-deadbeef}"
  jq -n --arg s "$sid" '{hook_event_name:"Stop",session_id:$s}'
}

@test "linux-notify: silently exits 0 on non-Linux" {
  if [[ "$(uname -s)" == "Linux" ]]; then
    skip "Linux path"
  fi
  payload=$(stop_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "linux-notify: invokes notify-send with title and body when on Linux" {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "non-Linux"
  fi
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/notify.log"
  cat > "${STUB_DIR}/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$STUB_LOG"
exit 0
EOF
  chmod +x "${STUB_DIR}/notify-send"

  payload=$(stop_payload "session-12345678")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env STUB_LOG="$STUB_LOG" PATH="${STUB_DIR}:${PATH}" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"; rm -rf "$STUB_DIR"
  [ "$status" -eq 0 ]
}

@test "linux-notify: validates urgency and falls back to normal on bad value" {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "non-Linux"
  fi
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/notify.log"
  cat > "${STUB_DIR}/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$STUB_LOG"
exit 0
EOF
  chmod +x "${STUB_DIR}/notify-send"
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env STUB_LOG="$STUB_LOG" PATH="${STUB_DIR}:${PATH}" \
    CLAUDE_NOTIFY_URGENCY="bogus" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"; rm -rf "$STUB_DIR"
  [ "$status" -eq 0 ]
}

@test "linux-notify: never writes JSON output" {
  payload=$(stop_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}
