#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/context/inject-git-context.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
  git init -q -b main
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

@test "happy path: writes git-status.md inside a git repo" {
  echo "dirty" >> a.txt
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  out="${TMPHOME}/.claude/context/git-status.md"
  [ -f "$out" ]
  grep -q "# Git Context" "$out"
  grep -q "## Branch" "$out"
  grep -q "main" "$out"
  grep -q "## Working Tree Status" "$out"
}

@test "outside a git repo: writes 'Not a git repository' note" {
  NONGIT=$(mktemp -d)
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$NONGIT' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  out="${TMPHOME}/.claude/context/git-status.md"
  [ -f "$out" ]
  grep -q "Not a git repository" "$out"
  rm -rf "$NONGIT"
}

@test "exits 0 with warning on invalid JSON stdin" {
  pfile=$(mktemp); printf 'not-json' > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ ! -f "${TMPHOME}/.claude/context/git-status.md" ]
}

@test "clean tree shows 'Clean — no uncommitted changes'" {
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  grep -q "Clean" "${TMPHOME}/.claude/context/git-status.md"
}
