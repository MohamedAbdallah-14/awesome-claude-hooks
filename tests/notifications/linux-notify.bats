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
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  # The stub records every notify-send invocation. If the hook short-circuited
  # without calling notify-send, STUB_LOG is empty and this test should fail.
  [ -s "$STUB_LOG" ]
  # The hook always passes a title argument starting with "Claude" (from
  # linux-notify.sh's title format). Asserting against the log catches a
  # silent regression that drops the call.
  grep -q "Claude" "$STUB_LOG"
  rm -rf "$STUB_DIR"
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
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  # notify-send must have been called with urgency=normal (the fallback),
  # never with the bogus value passed in via env.
  [ -s "$STUB_LOG" ]
  grep -q -- "--urgency=normal" "$STUB_LOG"
  ! grep -q -- "--urgency=bogus" "$STUB_LOG"
  rm -rf "$STUB_DIR"
}

@test "linux-notify: never writes JSON output" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  # Discard stderr — the hook's missing-binary warnings legitimately go
  # there. This assertion only cares about stdout staying empty.
  run bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  # Hook is observability-only; a regression that emits JSON for Claude
  # would still pass an exit-status-only test, so guard stdout explicitly.
  [ -z "$output" ]
}
