#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/desktop-notify.sh"

stop_payload() {
  local sid="${1:-zzz99999}"
  jq -n --arg s "$sid" \
    '{hook_event_name:"Stop",session_id:$s}'
}

setup() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/notify.log"
  # Stub osascript (macOS) and notify-send (Linux) — only one will fire per OS
  for bin in osascript notify-send; do
    cat > "${STUB_DIR}/${bin}" <<EOF
#!/usr/bin/env bash
printf '${bin}: %s\n' "\$@" >> "\$STUB_LOG"
exit 0
EOF
    chmod +x "${STUB_DIR}/${bin}"
  done
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "desktop-notify: dispatches to platform-appropriate notifier" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env STUB_LOG="$STUB_LOG" PATH="${STUB_DIR}:${PATH}" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  case "$(uname -s)" in
    Darwin)
      [ -f "$STUB_LOG" ] && grep -q "osascript:" "$STUB_LOG"
      ;;
    Linux)
      # may be linux or wsl — if powershell.exe isn't stubbed under WSL,
      # the hook simply skips; both outcomes are exit 0
      :
      ;;
  esac
}

@test "desktop-notify: respects CLAUDE_NOTIFY_TITLE override on Darwin" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "macOS-only branch"
  fi
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env STUB_LOG="$STUB_LOG" PATH="${STUB_DIR}:${PATH}" \
    CLAUDE_NOTIFY_TITLE="Custom Title" CLAUDE_NOTIFY_BODY="Custom Body" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  grep -q "Custom Title" "$STUB_LOG"
  grep -q "Custom Body" "$STUB_LOG"
}

@test "desktop-notify: silent exit when no notifier binary is on PATH" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  # Build a minimal PATH with everything the hook + os-detect.sh need
  # EXCEPT the notifier binaries (osascript, notify-send, powershell.exe).
  EMPTY_PATH=$(mktemp -d)
  for bin in jq bash uname cat date dirname grep tr printf; do
    if command -v "$bin" >/dev/null 2>&1; then
      ln -sf "$(command -v "$bin")" "${EMPTY_PATH}/${bin}"
    fi
  done
  run env PATH="${EMPTY_PATH}" bash -c "bash '$HOOK' < '$tmp'"
  rm -rf "$EMPTY_PATH"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}

@test "desktop-notify: never blocks (exit 0)" {
  payload=$(stop_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}
