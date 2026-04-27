#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/pushover-notify.sh"

stop_payload() {
  jq -n '{hook_event_name:"Stop",session_id:"sess-7"}'
}

setup() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/curl.log"
  cat > "${STUB_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
printf '{"status":1,"request":"abc"}'
exit 0
EOF
  chmod +x "${STUB_DIR}/curl"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "pushover-notify: silent when token missing" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env -u CLAUDE_PUSHOVER_TOKEN -u CLAUDE_PUSHOVER_USER \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "pushover-notify: silent when user key missing" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env -u CLAUDE_PUSHOVER_USER CLAUDE_PUSHOVER_TOKEN="aaa" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "pushover-notify: posts to messages.json with token+user form fields" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_PUSHOVER_TOKEN="tok-XYZ" \
    CLAUDE_PUSHOVER_USER="usr-ABC" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  grep -q "api.pushover.net/1/messages.json" "$STUB_LOG"
  grep -q "token=tok-XYZ" "$STUB_LOG"
  grep -q "user=usr-ABC" "$STUB_LOG"
}

@test "pushover-notify: clamps priority to 1" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_PUSHOVER_TOKEN="t" CLAUDE_PUSHOVER_USER="u" \
    CLAUDE_PUSHOVER_PRIORITY="2" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  grep -q "priority=1" "$STUB_LOG"
  ! grep -q "priority=2" "$STUB_LOG"
}
