#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/quality/php-pint-gate.sh"

setup() {
  STUBDIR=$(mktemp -d)
  JQ_DIR=$(dirname "$(command -v jq)")
  WORKDIR=$(mktemp -d)
  PHP_FILE="$WORKDIR/index.php"
  printf '<?php echo "hi";\n' > "$PHP_FILE"
  export STUBDIR JQ_DIR WORKDIR PHP_FILE
}

teardown() {
  rm -rf "$STUBDIR" "$WORKDIR"
}

write_stub() {
  local name="$1" body="$2"
  local dir="${3:-$STUBDIR}"
  mkdir -p "$dir"
  cat > "$dir/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$dir/$name"
}

@test "happy path: clean pint passes through" {
  write_stub pint 'exit 0'
  payload=$(posttool_payload Write "$PHP_FILE")
  PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || ! printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
}

@test "block path: pint --test failure emits deny JSON" {
  write_stub pint 'echo "STYLE issues found in index.php"; exit 1'
  payload=$(posttool_payload Write "$PHP_FILE")
  PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  assert_blocked_post
}

@test "block path: php -l fallback syntax error emits deny JSON" {
  write_stub php 'echo "Parse error: syntax error, unexpected end of file" >&2; exit 255'
  payload=$(posttool_payload Write "$PHP_FILE")
  # No pint stub — only php is available, hook should fall back to php -l.
  PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  assert_blocked_post
}

@test "bypass path: CLAUDE_PHP_PINT_GATE_SKIP=1 skips" {
  write_stub pint 'echo "would block"; exit 1'
  payload=$(posttool_payload Write "$PHP_FILE")
  CLAUDE_PHP_PINT_GATE_SKIP=1 PATH="$STUBDIR:$JQ_DIR:/usr/bin:/bin" \
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
  payload=$(posttool_payload Write "$PHP_FILE")
  PATH="$JQ_DIR:/usr/bin:/bin" run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
