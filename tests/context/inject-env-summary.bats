#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/context/inject-env-summary.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
}

teardown() {
  rm -rf "$TMPHOME"
}

stop_payload() {
  jq -n '{hook_event_name:"Stop",session_id:"t",stop_hook_active:false}'
}

@test "happy path: writes env-summary.md under \$HOME/.claude/context/" {
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "${TMPHOME}/.claude/context/env-summary.md" ]
  grep -q "# Environment Summary" "${TMPHOME}/.claude/context/env-summary.md"
  grep -q "## System" "${TMPHOME}/.claude/context/env-summary.md"
}

@test "respects CLAUDE_ENV_SUMMARY_INCLUDE_VERSIONS=0 (skips Tool Versions section)" {
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_ENV_SUMMARY_INCLUDE_VERSIONS=0 PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "${TMPHOME}/.claude/context/env-summary.md" ]
  ! grep -q "## Tool Versions" "${TMPHOME}/.claude/context/env-summary.md"
}

@test "exits 0 with warning on invalid JSON stdin" {
  pfile=$(mktemp); printf 'not-json' > "$pfile"
  run env HOME="$TMPHOME" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  # No file written
  [ ! -f "${TMPHOME}/.claude/context/env-summary.md" ]
}

@test "never emits env var values — only names" {
  # Set a sentinel value; the file must not contain it
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" MY_FAKE_SECRET="super-secret-value-xyz123" PATH="$PATH" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "${TMPHOME}/.claude/context/env-summary.md" ]
  # The variable name should appear, but never the value
  grep -q "MY_FAKE_SECRET" "${TMPHOME}/.claude/context/env-summary.md"
  ! grep -q "super-secret-value-xyz123" "${TMPHOME}/.claude/context/env-summary.md"
}
