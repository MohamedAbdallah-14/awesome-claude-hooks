#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/security/check-npm-audit.sh"

@test "allows non-install bash command" {
  payload=$(pretool_payload Bash "ls -la")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "warn-only: npm install passes through with reminder" {
  payload=$(pretool_payload Bash "npm install express")
  run_hook "$HOOK" "$payload"
  assert_allowed
  [[ "$output" == *"express"* ]]
  [[ "$output" == *"npm audit"* ]]
}

@test "warn-only: yarn add passes through with reminder" {
  payload=$(pretool_payload Bash "yarn add lodash")
  run_hook "$HOOK" "$payload"
  assert_allowed
  [[ "$output" == *"lodash"* ]]
}

@test "warn-only: pnpm add passes through with reminder" {
  payload=$(pretool_payload Bash "pnpm add react")
  run_hook "$HOOK" "$payload"
  assert_allowed
  [[ "$output" == *"react"* ]]
}

@test "blocks install when CLAUDE_NPM_AUDIT_BLOCK=1 and npm audit reports critical vulns" {
  tmpdir=$(mktemp -d)
  fakebin="${tmpdir}/bin"
  mkdir -p "$fakebin"
  cat > "${fakebin}/npm" <<'EOF'
#!/usr/bin/env bash
# Fake npm — emit a JSON audit report with a critical vulnerability.
echo '{"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":2,"total":2}}}'
EOF
  chmod +x "${fakebin}/npm"
  printf '{"name":"x","version":"0.0.0"}' > "${tmpdir}/package.json"

  payload=$(pretool_payload Bash "npm install lodash")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"

  run env CLAUDE_NPM_AUDIT_BLOCK=1 PATH="${fakebin}:${PATH}" \
    bash -c "cd '$tmpdir' && bash '$HOOK' < '$pfile'"

  rm -f "$pfile"
  rm -rf "$tmpdir"
  assert_blocked
  [[ "$output" == *"critical"* ]]
}

@test "bypass: unsetting CLAUDE_NPM_AUDIT_BLOCK keeps install in warn-only mode" {
  payload=$(pretool_payload Bash "npm install lodash")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env -u CLAUDE_NPM_AUDIT_BLOCK bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  assert_allowed
  [[ "$output" == *"lodash"* ]]
}

@test "ignores non-Bash tool (Write)" {
  payload=$(pretool_payload Write /tmp/foo.txt "npm install express")
  run_hook "$HOOK" "$payload"
  assert_allowed
}

@test "ignores empty bash command" {
  payload=$(pretool_payload Bash "")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
