#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/git/protect-main-branch.sh"

setup() {
  TMP_REPO=$(mktemp -d)
  (
    cd "$TMP_REPO"
    git init -q
    git checkout -q -b main 2>/dev/null || git -c init.defaultBranch=main init -q
    git config user.email test@example.com
    git config user.name test
    : > .keep
    git add .keep
    git commit -q -m "init"
  )
}

teardown() {
  rm -rf "$TMP_REPO"
}

# Run the hook with cwd set to the temp repo so `git symbolic-ref` resolves.
run_hook_in_repo() {
  local payload="$1"
  local tmp
  tmp=$(mktemp)
  printf '%s' "$payload" > "$tmp"
  run bash -c "cd '$TMP_REPO' && bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
}

@test "allows ordinary git push" {
  payload=$(pretool_payload Bash "git push origin feature-branch" "")
  run_hook_in_repo "$payload"
  assert_allowed
}

@test "allows force push to a non-protected branch" {
  payload=$(pretool_payload Bash "git push --force origin my-feature" "")
  run_hook_in_repo "$payload"
  assert_allowed
}

@test "blocks force push to main" {
  payload=$(pretool_payload Bash "git push --force origin main" "")
  run_hook_in_repo "$payload"
  assert_blocked
  [[ "$output" == *"main"* ]]
}

@test "blocks short -f push to master" {
  payload=$(pretool_payload Bash "git push -f origin master" "")
  run_hook_in_repo "$payload"
  assert_blocked
}

@test "blocks --force-with-lease to main" {
  payload=$(pretool_payload Bash "git push --force-with-lease origin main" "")
  run_hook_in_repo "$payload"
  assert_blocked
}

@test "blocks git reset --hard while on main" {
  payload=$(pretool_payload Bash "git reset --hard HEAD~1" "")
  run_hook_in_repo "$payload"
  assert_blocked
  [[ "$output" == *"main"* ]]
}

@test "allows git reset --hard while on feature branch" {
  (cd "$TMP_REPO" && git checkout -q -b feature)
  payload=$(pretool_payload Bash "git reset --hard HEAD~1" "")
  run_hook_in_repo "$payload"
  assert_allowed
}

@test "blocks git branch -D main" {
  payload=$(pretool_payload Bash "git branch -D main" "")
  run_hook_in_repo "$payload"
  assert_blocked
}

@test "blocks git checkout -B main" {
  payload=$(pretool_payload Bash "git checkout -B main origin/main" "")
  run_hook_in_repo "$payload"
  assert_blocked
}

@test "bypass via CLAUDE_ALLOW_FORCE_PUSH=1" {
  payload=$(pretool_payload Bash "git push --force origin main" "")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run bash -c "cd '$TMP_REPO' && CLAUDE_ALLOW_FORCE_PUSH=1 bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "respects CLAUDE_PROTECTED_BRANCHES override" {
  payload=$(pretool_payload Bash "git push --force origin release" "")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run bash -c "cd '$TMP_REPO' && CLAUDE_PROTECTED_BRANCHES='release staging' bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_blocked
  [[ "$output" == *"release"* ]]
}

@test "ignores non-Bash tools" {
  payload=$(pretool_payload Write /tmp/x.txt "git push --force origin main")
  run_hook_in_repo "$payload"
  assert_allowed
}

@test "ignores non-git Bash commands" {
  payload=$(pretool_payload Bash "ls -la" "")
  run_hook_in_repo "$payload"
  assert_allowed
}
