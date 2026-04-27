#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/automation/auto-changelog.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
  git init -q
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
  local tp="${1:-}"
  if [[ -n "$tp" ]]; then
    jq -n --arg p "$tp" '{hook_event_name:"Stop",session_id:"t",transcript_path:$p,stop_hook_active:false}'
  else
    jq -n '{hook_event_name:"Stop",session_id:"t",stop_hook_active:false}'
  fi
}

@test "opt-in gate: exits 0 with no changelog when CLAUDE_AUTO_CHANGELOG unset" {
  echo "dirty" >> a.txt
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ ! -f "${WORK}/CHANGELOG.md" ]
}

@test "happy path: enabled + changes present creates CHANGELOG.md" {
  echo "dirty" >> a.txt
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_CHANGELOG=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "${WORK}/CHANGELOG.md" ]
  grep -q "# Changelog" "${WORK}/CHANGELOG.md"
  grep -qE "^## [0-9]{4}-[0-9]{2}-[0-9]{2}" "${WORK}/CHANGELOG.md"
}

@test "silent skip: enabled but no changes — no entry added" {
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_CHANGELOG=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ ! -f "${WORK}/CHANGELOG.md" ]
}

@test "silent skip: enabled but not in a git repo" {
  NONGIT=$(mktemp -d)
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_CHANGELOG=1 bash -c "cd '$NONGIT' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ ! -f "${NONGIT}/CHANGELOG.md" ]
  rm -rf "$NONGIT"
}

@test "respects CLAUDE_CHANGELOG_FILE override" {
  echo "dirty" >> a.txt
  custom="${TMPHOME}/elsewhere.md"
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_CHANGELOG=1 CLAUDE_CHANGELOG_FILE="$custom" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  [ -f "$custom" ]
  [ ! -f "${WORK}/CHANGELOG.md" ]
}
