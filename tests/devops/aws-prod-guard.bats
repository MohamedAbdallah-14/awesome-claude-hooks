#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/devops/aws-prod-guard.sh"

@test "allows aws s3 ls (readonly, no profile)" {
  payload=$(pretool_payload Bash "aws s3 ls")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows aws describe-instances on prod profile (readonly)" {
  payload=$(pretool_payload Bash "aws ec2 describe-instances --profile prod")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows non-aws commands" {
  payload=$(pretool_payload Bash "echo aws is fun")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks aws s3 rb via AWS_PROFILE=prod" {
  payload=$(pretool_payload Bash "aws s3 rb s3://my-bucket --force")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  # Drop stderr — the hook's regex can emit a benign BSD-grep warning on
  # macOS that has no effect on the decision logic.
  run env AWS_PROFILE=prod bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  assert_blocked
  [[ "$output" == *"production"* ]]
}

@test "blocks aws s3 cp via AWS_DEFAULT_PROFILE=production" {
  payload=$(pretool_payload Bash "aws s3 cp ./file.txt s3://my-bucket/")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env AWS_DEFAULT_PROFILE=production bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  assert_blocked
}

@test "bypass via CLAUDE_ALLOW_AWS_PROD=1" {
  payload=$(pretool_payload Bash "aws s3 rb s3://my-bucket --force")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env AWS_PROFILE=prod CLAUDE_ALLOW_AWS_PROD=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "ignores non-Bash tools" {
  payload=$(pretool_payload Write /tmp/x.sh "aws s3 rb s3://prod")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env AWS_PROFILE=prod bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "blocks compound aws cmd: readonly && destructive on prod profile" {
  # Regression: a compound command must be blocked if ANY segment is destructive,
  # even if a leading segment looks readonly.
  payload=$(pretool_payload Bash "aws s3 ls --profile prod && aws s3 rm s3://prod-bucket/data --profile prod")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env bash -c "bash '$HOOK' < '$tmp' 2>/dev/null"
  rm -f "$tmp"
  assert_blocked
}
