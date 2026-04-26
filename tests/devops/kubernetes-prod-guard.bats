#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/devops/kubernetes-prod-guard.sh"

# Use an empty KUBECONFIG so kubectl current-context is not consulted
# during tests (avoids false positives from a developer's actual context).
setup() {
  export KUBECONFIG="/dev/null"
}

@test "allows kubectl get pods (no namespace flag)" {
  payload=$(pretool_payload Bash "kubectl get pods -n staging")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows kubectl get pods in dev namespace" {
  payload=$(pretool_payload Bash "kubectl get pods --namespace dev")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "allows non-kubectl commands" {
  payload=$(pretool_payload Bash "echo kubectl is fun")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "blocks kubectl with -n production" {
  payload=$(pretool_payload Bash "kubectl get pods -n production")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "blocks kubectl with --namespace production" {
  payload=$(pretool_payload Bash "kubectl delete pod foo --namespace production")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "blocks kubectl with prod context flag" {
  payload=$(pretool_payload Bash "kubectl --context my-prod-cluster get pods -n default")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "blocks kubectl delete without --namespace flag" {
  payload=$(pretool_payload Bash "kubectl delete pod my-pod")
  run_hook "$HOOK" "$payload"
  assert_blocked
  [[ "$output" == *"namespace"* ]]
}

@test "bypass via CLAUDE_ALLOW_K8S_PROD=1" {
  payload=$(pretool_payload Bash "kubectl delete pod foo --namespace production")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env KUBECONFIG=/dev/null CLAUDE_ALLOW_K8S_PROD=1 bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  assert_allowed
}

@test "ignores non-Bash tools" {
  payload=$(pretool_payload Write /tmp/x.sh "kubectl delete pod -n production foo")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
