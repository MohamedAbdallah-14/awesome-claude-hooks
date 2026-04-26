#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0
#
# Tests for hooks/ai/ai-migration-safety.sh.
#
# This hook calls Anthropic's Haiku API via `curl`. Tests must NOT make real
# network calls. Strategy: prepend a temp dir to PATH containing a fake `curl`
# that prints a controlled response (or fails) based on env vars.

load '../test_helper'

HOOK="${HOOKS_DIR}/ai/ai-migration-safety.sh"

setup() {
  STUB_DIR=$(mktemp -d)
  export STUB_DIR

  # Fake curl: behavior controlled by FAKE_CURL_MODE.
  #   verdict-irreversible / verdict-reversible / verdict-unknown
  #   verdict-malformed   -> valid JSON but no .content[0].text
  #   fail                -> exit non-zero (network error). Hook uses curl -sf
  #                         with `|| true`, so RESPONSE will be empty.
  cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
case "${FAKE_CURL_MODE:-}" in
  verdict-irreversible)
    cat <<'JSON'
{"content":[{"type":"text","text":"IRREVERSIBLE\nDropping a column is destructive and cannot be rolled back."}]}
JSON
    ;;
  verdict-reversible)
    cat <<'JSON'
{"content":[{"type":"text","text":"REVERSIBLE\nAdding a nullable column can be reverted by dropping it."}]}
JSON
    ;;
  verdict-unknown)
    cat <<'JSON'
{"content":[{"type":"text","text":"UNKNOWN\nNot enough info to assess."}]}
JSON
    ;;
  verdict-malformed)
    echo '{"error":"oops"}'
    ;;
  fail)
    # Mimic a network/HTTP failure under `curl -sf`: no stdout, non-zero exit.
    exit 22
    ;;
  *)
    echo "FAKE CURL: unset FAKE_CURL_MODE" >&2
    exit 99
    ;;
esac
STUB
  chmod +x "$STUB_DIR/curl"
}

teardown() {
  [[ -n "${STUB_DIR:-}" && -d "$STUB_DIR" ]] && rm -rf "$STUB_DIR"
}

# Run the hook with a fresh PATH that puts the curl stub in front and a chosen
# ANTHROPIC_API_KEY / FAKE_CURL_MODE. Sets bats $status, $output.
run_hook_with_stub() {
  # Note: use ${VAR-default} (not ${VAR:-default}) so an explicit empty-string
  # key/mode passed by the caller is preserved.
  local payload="$1" mode="${2-}" key="${3-test-key}"
  local tmp; tmp=$(mktemp)
  printf '%s' "$payload" > "$tmp"
  run env \
    PATH="$STUB_DIR:$PATH" \
    ANTHROPIC_API_KEY="$key" \
    FAKE_CURL_MODE="$mode" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
}

@test "no API key: passes through on a migration command" {
  payload=$(pretool_payload Bash "rails db:migrate")
  # Empty key triggers the early skip; stub curl should never be invoked.
  run_hook_with_stub "$payload" "" ""
  assert_allowed
  [ -z "$output" ]
}

@test "no API key: passes through on a non-migration command" {
  payload=$(pretool_payload Bash "ls -la")
  run_hook_with_stub "$payload" "" ""
  assert_allowed
}

@test "non-migration bash command: passes through even with API key" {
  payload=$(pretool_payload Bash "echo migrate is just a word here")
  # Word "migrate" is not a standalone token at the head of an arg, regex is
  # word-bounded. This should skip before reaching curl. Set mode=fail so that
  # if curl WERE called, the hook would still allow — but it shouldn't be.
  run_hook_with_stub "$payload" "fail" "test-key"
  assert_allowed
}

@test "migration command + IRREVERSIBLE verdict: blocks with deny JSON" {
  payload=$(pretool_payload Bash "alembic upgrade head")
  run_hook_with_stub "$payload" "verdict-irreversible" "test-key"
  assert_blocked
  [[ "$output" == *"IRREVERSIBLE"* ]]
}

@test "migration command + REVERSIBLE verdict: passes through" {
  payload=$(pretool_payload Bash "rails db:migrate")
  run_hook_with_stub "$payload" "verdict-reversible" "test-key"
  assert_allowed
  # No deny JSON on stdout.
  [[ "$output" != *"\"permissionDecision\""* ]]
}

@test "migration command + UNKNOWN verdict: passes through" {
  payload=$(pretool_payload Bash "flyway migrate")
  run_hook_with_stub "$payload" "verdict-unknown" "test-key"
  assert_allowed
  [[ "$output" != *"\"permissionDecision\""* ]]
}

@test "migration command + curl network error: graceful degrade (allows)" {
  payload=$(pretool_payload Bash "liquibase update")
  run_hook_with_stub "$payload" "fail" "test-key"
  assert_allowed
}

@test "migration command + malformed API response: allows (no .content text)" {
  payload=$(pretool_payload Bash "rails db:migrate")
  run_hook_with_stub "$payload" "verdict-malformed" "test-key"
  assert_allowed
}

@test "non-Bash tool: passes through" {
  payload=$(pretool_payload Write /tmp/x.sql "rails db:migrate")
  run_hook_with_stub "$payload" "verdict-irreversible" "test-key"
  assert_allowed
}
