#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/sound-error.sh"

# PostToolUse payload — exit code controls whether the hook plays a sound.
post_payload() {
  local exit_code="${1:-0}"
  local stderr_text="${2:-}"
  jq -n --argjson c "$exit_code" --arg s "$stderr_text" '{
    hook_event_name:"PostToolUse",
    session_id:"x",
    tool_name:"Bash",
    tool_input:{command:"true"},
    tool_response:{exit_code:$c,stderr:$s}
  }'
}

setup() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/play.log"
  for bin in afplay paplay aplay; do
    cat > "${STUB_DIR}/${bin}" <<EOF
#!/usr/bin/env bash
printf '${bin}: %s\n' "\$*" >> "\$STUB_LOG"
exit 0
EOF
    chmod +x "${STUB_DIR}/${bin}"
  done
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "sound-error: silent when exit_code is 0 and stderr is empty" {
  payload=$(post_payload 0 "")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}

@test "sound-error: plays sound when exit_code is non-zero" {
  if [[ "$(uname -s)" != "Darwin" && "$(uname -s)" != "Linux" ]]; then
    skip "unsupported OS"
  fi
  payload=$(post_payload 1 "")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  # Hook backgrounds the player; poll for the stub to flush.
  run env PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null; for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s '$STUB_LOG' ] && break; sleep 0.1; done"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -s "$STUB_LOG" ]
}

@test "sound-error: plays sound when stderr contains 'Error'" {
  if [[ "$(uname -s)" != "Darwin" && "$(uname -s)" != "Linux" ]]; then
    skip "unsupported OS"
  fi
  payload=$(post_payload 0 "Some Error happened")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null; for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s '$STUB_LOG' ] && break; sleep 0.1; done"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -s "$STUB_LOG" ]
}

@test "sound-error: never writes JSON to stdout" {
  payload=$(post_payload 1 "")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}
