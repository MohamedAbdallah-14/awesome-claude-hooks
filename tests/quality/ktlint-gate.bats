#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/quality/ktlint-gate.sh"

setup() {
  STUBDIR=$(mktemp -d)
  JQ_DIR=$(dirname "$(command -v jq)")
  WORKDIR=$(mktemp -d)
  KT_FILE="$WORKDIR/Main.kt"
  printf 'fun main() {}\n' > "$KT_FILE"
  export STUBDIR JQ_DIR WORKDIR KT_FILE
}

teardown() {
  rm -rf "$STUBDIR" "$WORKDIR"
}

write_stub() {
  local name="$1" body="$2"
  cat > "$STUBDIR/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$STUBDIR/$name"
}

@test "happy path: clean ktlint passes through" {
  write_stub ktlint 'exit 0'
  payload=$(posttool_payload Write "$KT_FILE")
  PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || ! printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
}

@test "block path: ktlint failure emits deny JSON" {
  write_stub ktlint 'echo "$1:1:1: Wildcard import (no-wildcard-imports)"; exit 1'
  payload=$(posttool_payload Write "$KT_FILE")
  PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  assert_blocked_post
}

@test "bypass path: CLAUDE_KTLINT_GATE_SKIP=1 skips" {
  write_stub ktlint 'echo "would block"; exit 1'
  payload=$(posttool_payload Write "$KT_FILE")
  CLAUDE_KTLINT_GATE_SKIP=1 PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" \
    run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "non-matching extension passes through" {
  payload=$(posttool_payload Write /tmp/x.txt)
  run_hook "$HOOK" "$payload"
  assert_allowed
  [ -z "$output" ]
}

@test "missing linter binary silently skips" {
  payload=$(posttool_payload Write "$KT_FILE")
  PATH="$JQ_DIR:/usr/bin:/bin" run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
