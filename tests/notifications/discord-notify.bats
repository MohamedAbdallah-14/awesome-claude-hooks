#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/discord-notify.sh"

stop_payload() {
  jq -n '{hook_event_name:"Stop",session_id:"abcdef"}'
}

setup() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/curl.log"
  cat > "${STUB_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
printf '204'
exit 0
EOF
  chmod +x "${STUB_DIR}/curl"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "discord-notify: silent when CLAUDE_DISCORD_WEBHOOK unset" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env -u CLAUDE_DISCORD_WEBHOOK PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "discord-notify: posts to configured webhook URL" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_DISCORD_WEBHOOK="https://discord.example/webhooks/123/abc" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  grep -q "discord.example/webhooks/123/abc" "$STUB_LOG"
}

@test "discord-notify: never writes JSON to stdout" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_DISCORD_WEBHOOK="https://discord.example/x" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
