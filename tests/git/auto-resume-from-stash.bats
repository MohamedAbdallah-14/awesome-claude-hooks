#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/git/auto-resume-from-stash.sh"

setup() {
  TMP_REPO="$(mktemp -d)"
  git -C "$TMP_REPO" init -q -b main
  git -C "$TMP_REPO" config user.email "t@t.t"
  git -C "$TMP_REPO" config user.name "t"
  echo "hello" > "$TMP_REPO/a.txt"
  git -C "$TMP_REPO" add a.txt
  git -C "$TMP_REPO" -c commit.gpgsign=false commit -q -m "init"
}

teardown() {
  rm -rf "$TMP_REPO"
}

resume_payload() {
  jq -n --arg cwd "$TMP_REPO" '{
    hook_event_name: "SessionStart",
    session_id: "test",
    source: "resume",
    cwd: $cwd
  }'
}

@test "auto-resume-from-stash: hook is executable" {
  [ -x "$HOOK" ]
}

@test "no matching stash: no output, no change" {
  payload=$(resume_payload)
  run_hook "$HOOK" "$payload"
  assert_allowed
  [ -z "$output" ]
}

@test "non-resume source: no-op" {
  payload=$(jq -n --arg cwd "$TMP_REPO" '{
    hook_event_name: "SessionStart",
    source: "startup",
    cwd: $cwd
  }')
  run_hook "$HOOK" "$payload"
  assert_allowed
  [ -z "$output" ]
}

@test "pops a matching claude-auto stash on the current branch" {
  # Create a dirty file, stash with the magic prefix, then resume.
  echo "in-progress" > "$TMP_REPO/work.txt"
  git -C "$TMP_REPO" add work.txt
  git -C "$TMP_REPO" stash push -u -q -m "claude-auto: main"

  # Branch is clean now.
  payload=$(resume_payload)
  run_hook "$HOOK" "$payload"
  assert_allowed

  # Output should announce the pop.
  printf '%s' "$output" | jq -e \
    '.hookSpecificOutput.hookEventName == "SessionStart"
     and (.hookSpecificOutput.additionalContext | contains("popped"))' \
    >/dev/null

  # Stashed file should be back.
  [ -f "$TMP_REPO/work.txt" ]

  # Stash list should now be empty.
  list=$(git -C "$TMP_REPO" stash list)
  [ -z "$list" ]
}

@test "ignores stashes without the claude-auto prefix" {
  echo "manual" > "$TMP_REPO/manual.txt"
  git -C "$TMP_REPO" add manual.txt
  git -C "$TMP_REPO" stash push -u -q -m "WIP: my own stash"

  payload=$(resume_payload)
  run_hook "$HOOK" "$payload"
  assert_allowed
  [ -z "$output" ]

  # Stash should still be there.
  list=$(git -C "$TMP_REPO" stash list)
  [[ "$list" == *"WIP: my own stash"* ]]
}

@test "skips pop if working tree is dirty" {
  echo "stash-me" > "$TMP_REPO/stashed.txt"
  git -C "$TMP_REPO" add stashed.txt
  git -C "$TMP_REPO" stash push -u -q -m "claude-auto: main"

  # Now make the tree dirty.
  echo "dirty" > "$TMP_REPO/dirty.txt"

  payload=$(resume_payload)
  run_hook "$HOOK" "$payload"
  assert_allowed

  printf '%s' "$output" | jq -e \
    '.hookSpecificOutput.additionalContext | contains("dirty")' \
    >/dev/null

  # Stash should be untouched.
  list=$(git -C "$TMP_REPO" stash list)
  [[ "$list" == *"claude-auto: main"* ]]
}

@test "bypass via CLAUDE_AUTO_RESUME_STASH_OFF=1" {
  echo "stash-me" > "$TMP_REPO/stashed.txt"
  git -C "$TMP_REPO" add stashed.txt
  git -C "$TMP_REPO" stash push -u -q -m "claude-auto: main"

  payload=$(resume_payload)
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_AUTO_RESUME_STASH_OFF=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # Stash still there.
  list=$(git -C "$TMP_REPO" stash list)
  [[ "$list" == *"claude-auto: main"* ]]
}

@test "ignores claude-auto stashes from a different branch" {
  echo "stash-me" > "$TMP_REPO/stashed.txt"
  git -C "$TMP_REPO" add stashed.txt
  git -C "$TMP_REPO" stash push -u -q -m "claude-auto: feature/other"

  # Still on main.
  payload=$(resume_payload)
  run_hook "$HOOK" "$payload"
  assert_allowed
  [ -z "$output" ]

  list=$(git -C "$TMP_REPO" stash list)
  [[ "$list" == *"feature/other"* ]]
}
