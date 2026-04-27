#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0
#
# auto-push.sh requires a real git remote to fully exercise. Here we cover
# only the dry-run-style guards (opt-in gate, branch protection, non-claude
# commit, missing upstream + missing origin). Pushing to a real remote is
# intentionally out of scope.

load '../test_helper'

HOOK="${HOOKS_DIR}/automation/auto-push.sh"

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

@test "opt-in gate: disabled by default — exits 0 with no output" {
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "branch protection: refuses to push from main" {
  git -C "$WORK" checkout -q -b main
  git -C "$WORK" commit -q --allow-empty -m "claude: dummy"
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_PUSH=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "protected branch"
}

@test "skip when last commit is not by Claude" {
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_PUSH=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "Last commit was not made by Claude"
}

@test "skip when no upstream and no origin remote configured" {
  git -C "$WORK" commit -q --allow-empty -m "claude: dummy work"
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_PUSH=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "no 'origin' remote"
}

@test "silent skip: not in a git repo" {
  NONGIT=$(mktemp -d)
  payload=$(stop_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  # Capture stdout only — stderr is allowed to carry a one-line "skipping"
  # diagnostic. Stdout is what reaches Claude as JSON, and the hook MUST
  # NOT emit anything there for the non-git case (so a regression that
  # accidentally prints a git error or set -u trace to stdout fails here).
  run env HOME="$TMPHOME" CLAUDE_AUTO_PUSH=1 bash -c "cd '$NONGIT' && bash '$HOOK' < '$pfile' 2>/dev/null"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$NONGIT"
}
