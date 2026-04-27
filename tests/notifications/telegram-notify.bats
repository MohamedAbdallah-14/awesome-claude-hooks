#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/telegram-notify.sh"

stop_payload() {
  jq -n '{hook_event_name:"Stop",session_id:"sess123"}'
}

setup() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/curl.log"
  cat > "${STUB_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
printf '{"ok":true,"result":{"message_id":1}}'
exit 0
EOF
  chmod +x "${STUB_DIR}/curl"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "telegram-notify: silent when bot token missing" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env -u CLAUDE_TELEGRAM_BOT_TOKEN -u CLAUDE_TELEGRAM_CHAT_ID \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "telegram-notify: silent when chat id missing" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env -u CLAUDE_TELEGRAM_CHAT_ID CLAUDE_TELEGRAM_BOT_TOKEN="123:abc" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "telegram-notify: calls Telegram Bot API with token in URL" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_TELEGRAM_BOT_TOKEN="111:secret" \
    CLAUDE_TELEGRAM_CHAT_ID="42" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  grep -q "api.telegram.org/bot111:secret/sendMessage" "$STUB_LOG"
}
