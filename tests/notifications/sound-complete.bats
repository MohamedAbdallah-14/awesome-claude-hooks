#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/sound-complete.sh"

stop_payload() {
  jq -n '{hook_event_name:"Stop",session_id:"a"}'
}

setup() {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/play.log"
  for bin in afplay paplay aplay; do
    cat > "${STUB_DIR}/${bin}" <<EOF
#!/usr/bin/env bash
{
  printf '${bin}: %s\n' "\$*" >> "\$STUB_LOG"
} 2>/dev/null
sync 2>/dev/null || true
exit 0
EOF
    chmod +x "${STUB_DIR}/${bin}"
  done
}

teardown() {
  rm -rf "$STUB_DIR"
}

@test "sound-complete: plays default system sound on Darwin" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "macOS only"
  fi
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  # Hook backgrounds afplay; poll briefly so the stub log has flushed before
  # we assert. Without this the assertion races the background process.
  run env PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'; for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s '$STUB_LOG' ] && break; sleep 0.1; done"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  # Real assertion (was previously neutralised by `|| true`): the hook MUST
  # have invoked afplay. A regression that silently drops the call should fail.
  [ -s "$STUB_LOG" ]
  grep -q "^afplay:" "$STUB_LOG"
}

@test "sound-complete: respects CLAUDE_SOUND_COMPLETE override" {
  if [[ "$(uname -s)" != "Darwin" && "$(uname -s)" != "Linux" ]]; then
    skip "unsupported OS"
  fi
  CUSTOM=$(mktemp -t soundXXXX)
  : > "$CUSTOM"
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  # Hook backgrounds afplay/paplay; the wait-loop polls until the stub flushes.
  run env PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    CLAUDE_SOUND_COMPLETE="$CUSTOM" \
    bash -c "bash '$HOOK' < '$tmp'; for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s '$STUB_LOG' ] && break; sleep 0.1; done"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -s "$STUB_LOG" ]
  grep -q "$(basename "$CUSTOM")" "$STUB_LOG"
  rm -f "$CUSTOM"
}

@test "sound-complete: warns but exits 0 when override file is missing" {
  payload=$(stop_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    CLAUDE_SOUND_COMPLETE="/nonexistent/sound.aiff" \
    bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
}

@test "sound-complete: never blocks (no JSON deny)" {
  payload=$(stop_payload)
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}
