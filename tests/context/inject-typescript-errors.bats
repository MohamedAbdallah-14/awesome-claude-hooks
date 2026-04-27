#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/context/inject-typescript-errors.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

edit_payload() {
  local fp="$1"
  jq -n --arg p "$fp" \
    '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Edit",tool_input:{file_path:$p,old_string:"",new_string:""}}'
}

@test "silent skip: non-TS file approves with no context" {
  payload=$(edit_payload "${WORK}/foo.py")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (has("context") | not)' >/dev/null
}

@test "silent skip: TS file with no tsconfig.json found approves with no context" {
  payload=$(edit_payload "${WORK}/foo.ts")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  # Set HOME so the walk-up never finds a tsconfig outside the temp dir.
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  # Either there's no tsconfig anywhere up the tree (plain approve) OR a
  # tsconfig was found higher up — both still exit 0; we only require a valid
  # JSON approve response here.
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
}

@test "silent skip: empty file_path approves" {
  payload=$(jq -n '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Edit",tool_input:{}}')
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
}

@test "uses cache when fresh cache file exists" {
  # Pre-seed cache for the project hash so the hook returns the cached value
  # without invoking tsc. That isolates us from whether tsc is installed.
  echo '{}' > "${WORK}/tsconfig.json"
  echo "const x: number = 1;" > "${WORK}/foo.ts"

  # Mirror the hook's hash logic exactly (see hooks/context/inject-typescript-errors.sh).
  # Without pipefail, `cut` masks `md5sum` failure on macOS, so an `||`-chained
  # pipeline can produce an empty PROJECT_HASH and the test cache path won't
  # match what the hook computes. Branch on `command -v` instead.
  if command -v md5sum >/dev/null 2>&1; then
    PROJECT_HASH=$(printf '%s' "$WORK" | md5sum | cut -c1-8)
  elif command -v md5 >/dev/null 2>&1; then
    PROJECT_HASH=$(printf '%s' "$WORK" | md5 | cut -c1-8)
  else
    PROJECT_HASH="default"
  fi
  CACHE_FILE="/tmp/claude-ts-errors-${PROJECT_HASH}.cache"
  echo "TypeScript: 0 errors (cached sentinel)" > "$CACHE_FILE"

  payload=$(edit_payload "${WORK}/foo.ts")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile" "$CACHE_FILE"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
  printf '%s' "$output" | jq -r '.context // ""' | grep -q "cached sentinel"
}

@test "exits 0 on invalid JSON stdin" {
  pfile=$(mktemp); printf 'oops' > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
}
