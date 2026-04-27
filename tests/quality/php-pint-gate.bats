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
  # Listing /usr/bin and /bin lets a host-installed php/pint leak in and
  # run the real linter, making this assertion non-deterministic across CI
  # hosts. Pin PATH to a clean dir that contains only the few utilities the
  # hook itself needs (cat for stdin, bash/sh/env for shebang resolution),
  # plus the jq stub. Without php/pint anywhere on PATH the hook's
  # `command -v pint`/`command -v php` checks both miss and it takes its
  # silent-skip branch deterministically.
  CLEAN=$(mktemp -d)
  for b in cat bash sh env; do
    real="$(/usr/bin/env which "$b" 2>/dev/null || true)"
    if [[ -n "$real" && -x "$real" ]]; then
      ln -sf "$real" "$CLEAN/$b"
    fi
  done
  PATH="$JQ_DIR:$CLEAN" run bash -c "printf '%s' '$payload' | bash '$HOOK'"
  rm -rf "$CLEAN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
