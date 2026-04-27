#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/slack-notify.sh"

stop_payload() {
  local sid="${1:-sess-1}"
  jq -n --arg s "$sid" '{hook_event_name:"Stop",session_id:$s}'
}

setup() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/curl.log"
  # Stub curl: log args + body, return HTTP 200
  cat > "${STUB_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS: %s\n' "$*" >> "$STUB_LOG"
# Drain any stdin payload (curl accepts -d but reads stdin too)
printf '200'
exit 0
EOF
  chmod +x "${STUB_DIR}/curl"
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "slack-notify: silent exit when CLAUDE_SLACK_WEBHOOK is unset" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env -u CLAUDE_SLACK_WEBHOOK PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  # curl must NOT have been called
  [ ! -s "$STUB_LOG" ]
}

@test "slack-notify: posts to webhook URL when configured" {
  payload=$(stop_payload "abcdef0123")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_SLACK_WEBHOOK="https://hooks.slack.example/T/B/X" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -f "$STUB_LOG" ]
  grep -q "https://hooks.slack.example" "$STUB_LOG"
}

@test "slack-notify: includes channel override in payload when set" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  # Stub curl that captures the JSON body from -d arg
  cat > "${STUB_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
# find the value after -d
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-d" ]]; then
    printf 'BODY: %s\n' "$arg" >> "$STUB_LOG"
  fi
  prev="$arg"
done
printf '200'
exit 0
EOF
  chmod +x "${STUB_DIR}/curl"
  run env CLAUDE_SLACK_WEBHOOK="https://hooks.slack.example/x" \
    CLAUDE_SLACK_CHANNEL="#alerts" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  # jq pretty-prints by default → "channel": "#alerts" (with whitespace)
  grep -q '"#alerts"' "$STUB_LOG"
  grep -q 'channel' "$STUB_LOG"
}

@test "slack-notify: silent exit when curl is missing" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  EMPTY=$(mktemp -d)
  for bin in jq bash uname cat date; do
    [[ -x "$(command -v "$bin")" ]] && ln -sf "$(command -v "$bin")" "${EMPTY}/${bin}"
  done
  run env CLAUDE_SLACK_WEBHOOK="https://x.example" PATH="${EMPTY}" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -rf "$EMPTY"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}
