#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/automation/auto-prettier.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

posttool_payload() {
  local fp="$1"
  jq -n --arg p "$fp" \
    '{hook_event_name:"PostToolUse",session_id:"t",tool_name:"Write",tool_input:{file_path:$p}}'
}

@test "happy path: prettier-eligible file exits 0 (formats or warns gracefully)" {
  echo "const x=1" > "${WORK}/a.ts"
  payload=$(posttool_payload "${WORK}/a.ts")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
}

@test "silent skip: unsupported extension — no output, exit 0" {
  echo "x" > "${WORK}/a.unsupported"
  payload=$(posttool_payload "${WORK}/a.unsupported")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent skip: file does not exist — exit 0" {
  payload=$(posttool_payload "${WORK}/missing.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "skip pattern: node_modules path is skipped" {
  mkdir -p "${WORK}/node_modules/x"
  echo '{"a":1}' > "${WORK}/node_modules/x/a.json"
  payload=$(posttool_payload "${WORK}/node_modules/x/a.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi "skip"
}

@test "respects custom CLAUDE_PRETTIER_SKIP_PATTERNS" {
  mkdir -p "${WORK}/generated"
  echo '{"a":1}' > "${WORK}/generated/a.json"
  payload=$(posttool_payload "${WORK}/generated/a.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_PRETTIER_SKIP_PATTERNS="generated" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi "generated"
}
