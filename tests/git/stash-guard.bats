#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/git/stash-guard.sh"

setup() {
  TMP_REPO=$(mktemp -d)
  (
    cd "$TMP_REPO"
    git init -q
    git checkout -q -b main 2>/dev/null || git -c init.defaultBranch=main init -q
    git config user.email test@example.com
    git config user.name test
    printf 'initial\n' > file.txt
    git add file.txt
    git commit -q -m "init"
  )
}

teardown() {
  rm -rf "$TMP_REPO"
}

dirty_repo() {
  printf 'dirty change\n' >> "$TMP_REPO/file.txt"
}

# Run the hook with cwd inside the temp repo, optionally with extra env.
run_hook_in_repo() {
  local payload="$1"
  local env_prefix="${2:-}"
  local tmp
  tmp=$(mktemp)
  printf '%s' "$payload" > "$tmp"
  run bash -c "cd '$TMP_REPO' && ${env_prefix} bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
}

@test "allows risky command when working tree is clean" {
  payload=$(pretool_payload Bash "git checkout feature" "")
  run_hook_in_repo "$payload"
  assert_allowed
}

@test "warns (approves) on git checkout with dirty tree" {
  dirty_repo
  payload=$(pretool_payload Bash "git checkout other-branch" "")
  run_hook_in_repo "$payload"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "expected approve (warn), got deny: $output" >&2
    return 1
  fi
  [[ "$output" == *"approve"* ]]
}

@test "warns on git pull with dirty tree" {
  dirty_repo
  payload=$(pretool_payload Bash "git pull" "")
  run_hook_in_repo "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *"approve"* ]]
}

@test "warns on git stash pop with dirty tree" {
  dirty_repo
  payload=$(pretool_payload Bash "git stash pop" "")
  run_hook_in_repo "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *"approve"* ]]
}

@test "warns on git reset --hard with dirty tree" {
  dirty_repo
  payload=$(pretool_payload Bash "git reset --hard HEAD" "")
  run_hook_in_repo "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *"approve"* ]]
}

@test "warns on git merge with dirty tree" {
  dirty_repo
  payload=$(pretool_payload Bash "git merge feature" "")
  run_hook_in_repo "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *"approve"* ]]
}

@test "blocks risky command with CLAUDE_STASH_GUARD_BLOCK=1 and dirty tree" {
  dirty_repo
  payload=$(pretool_payload Bash "git checkout other" "")
  run_hook_in_repo "$payload" "CLAUDE_STASH_GUARD_BLOCK=1"
  assert_blocked
  [[ "$output" == *"checkout"* || "$output" == *"branch switch"* || "$output" == *"Stash"* || "$output" == *"stash"* ]]
}

@test "bypass via CLAUDE_STASH_GUARD_SKIP=1 even with block flag" {
  dirty_repo
  payload=$(pretool_payload Bash "git checkout other" "")
  run_hook_in_repo "$payload" "CLAUDE_STASH_GUARD_BLOCK=1 CLAUDE_STASH_GUARD_SKIP=1"
  assert_allowed
}

@test "ignores non-Bash tools" {
  dirty_repo
  payload=$(pretool_payload Write /tmp/x.txt "git checkout main")
  run_hook_in_repo "$payload"
  assert_allowed
}

@test "ignores non-monitored git commands" {
  dirty_repo
  payload=$(pretool_payload Bash "git status" "")
  run_hook_in_repo "$payload"
  assert_allowed
}
