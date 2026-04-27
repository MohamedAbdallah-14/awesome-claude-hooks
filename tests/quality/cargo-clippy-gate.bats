#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/quality/cargo-clippy-gate.sh"

setup() {
  STUBDIR=$(mktemp -d)
  JQ_DIR=$(dirname "$(command -v jq)")
  WORKDIR=$(mktemp -d)
  RS_FILE="$WORKDIR/lib.rs"
  printf 'fn main() {}\n' > "$RS_FILE"
  printf '[package]\nname = "x"\nversion = "0.1.0"\n' > "$WORKDIR/Cargo.toml"
  export STUBDIR JQ_DIR WORKDIR RS_FILE
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

@test "happy path: clean clippy passes through" {
  write_stub cargo 'exit 0'
  payload=$(posttool_payload Write "$RS_FILE")
  PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" run bash -c "cd '$WORKDIR' && printf '%s' '$payload' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || ! printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
}

@test "block path: clippy warning emits deny JSON" {
  write_stub cargo 'echo "warning: unused variable" >&2; exit 101'
  payload=$(posttool_payload Write "$RS_FILE")
  PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" run bash -c "cd '$WORKDIR' && printf '%s' '$payload' | bash '$HOOK'"
  assert_blocked_post
}

@test "bypass path: CLAUDE_CARGO_CLIPPY_GATE_SKIP=1 skips" {
  write_stub cargo 'echo "would block" >&2; exit 101'
  payload=$(posttool_payload Write "$RS_FILE")
  CLAUDE_CARGO_CLIPPY_GATE_SKIP=1 PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" \
    run bash -c "cd '$WORKDIR' && printf '%s' '$payload' | bash '$HOOK'"
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
  payload=$(posttool_payload Write "$RS_FILE")
  PATH="$JQ_DIR:/usr/bin:/bin" run bash -c "cd '$WORKDIR' && printf '%s' '$payload' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
