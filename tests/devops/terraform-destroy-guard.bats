#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/devops/terraform-destroy-guard.sh"

@test "allows terraform plan" {
  payload=$(pretool_payload Bash "terraform plan")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows terraform apply (no -destroy)" {
  payload=$(pretool_payload Bash "terraform apply -auto-approve")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks terraform destroy" {
  payload=$(pretool_payload Bash "terraform destroy -auto-approve")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"terraform destroy"* ]]
}

@test "blocks terraform -chdir=infra destroy" {
  payload=$(pretool_payload Bash "terraform -chdir=infra destroy")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "warns but allows terraform apply -destroy" {
  payload=$(pretool_payload Bash "terraform apply -destroy -auto-approve")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "bypass via CLAUDE_ALLOW_DESTROY=1" {
  payload=$(pretool_payload Bash "terraform destroy -auto-approve")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env CLAUDE_ALLOW_DESTROY=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "ignores non-Bash tools" {
  payload=$(pretool_payload Write /tmp/x.tf "terraform destroy")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "ignores non-terraform commands" {
  payload=$(pretool_payload Bash "echo destroy everything")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
