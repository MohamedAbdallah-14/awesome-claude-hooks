#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/automation/auto-git-commit.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
  git init -q -b feature
  git config user.email "test@test"
  git config user.name "Test"
  echo "x" > a.txt
  git add a.txt
  git commit -q -m "init"
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

stop_payload() {
  jq -n '{hook_event_name:"Stop",session_id:"t",stop_hook_active:false}'
}

@test "opt-in gate: disabled by default — no commit even with changes" {
  echo "dirty" >> a.txt
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  # uncommitted changes should remain
  [ -n "$(git -C "$WORK" status --porcelain)" ]
}

@test "happy path: enabled + on feature branch + dirty tree commits" {
  echo "dirty" >> a.txt
  HEAD_BEFORE=$(git -C "$WORK" rev-parse HEAD)
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_COMMIT=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  HEAD_AFTER=$(git -C "$WORK" rev-parse HEAD)
  [ "$HEAD_BEFORE" != "$HEAD_AFTER" ]
  git -C "$WORK" log -1 --format=%s | grep -q "^claude:"
}

@test "branch protection: refuses to commit on main" {
  git -C "$WORK" checkout -q -b main
  echo "dirty" >> a.txt
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_COMMIT=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -n "$(git -C "$WORK" status --porcelain)" ]
}

@test "silent skip: enabled but no changes — exits 0, no commit" {
  HEAD_BEFORE=$(git -C "$WORK" rev-parse HEAD)
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_COMMIT=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  HEAD_AFTER=$(git -C "$WORK" rev-parse HEAD)
  [ "$HEAD_BEFORE" = "$HEAD_AFTER" ]
}

@test "silent skip: enabled but not in a git repo" {
  NONGIT=$(mktemp -d)
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_COMMIT=1 bash -c "cd '$NONGIT' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  rm -rf "$NONGIT"
}
