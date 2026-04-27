#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/automation/auto-format-on-save.sh"

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

@test "happy path: known extension — runs (or warns when formatter missing) and exits 0" {
  echo "const x = 1" > "${WORK}/a.ts"
  payload=$(posttool_payload "${WORK}/a.ts")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
}

@test "silent skip: unknown extension exits 0 with no output" {
  echo "data" > "${WORK}/a.unknownext"
  payload=$(posttool_payload "${WORK}/a.unknownext")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent skip: file does not exist — exits 0" {
  payload=$(posttool_payload "${WORK}/missing.ts")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
}

@test "disabled gate: CLAUDE_AUTOFORMAT_ENABLED=0 short-circuits exit 0" {
  echo "x" > "${WORK}/a.py"
  payload=$(posttool_payload "${WORK}/a.py")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTOFORMAT_ENABLED=0 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "respects CLAUDE_AUTOFORMAT_SKIP_TYPES — skips listed extension" {
  echo "x = 1" > "${WORK}/a.py"
  payload=$(posttool_payload "${WORK}/a.py")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTOFORMAT_SKIP_TYPES="py" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "skip list"
}

@test "skips vendored paths (node_modules)" {
  mkdir -p "${WORK}/node_modules/foo"
  echo "x" > "${WORK}/node_modules/foo/a.ts"
  payload=$(posttool_payload "${WORK}/node_modules/foo/a.ts")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
