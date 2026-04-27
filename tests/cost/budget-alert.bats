#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/cost/budget-alert.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  # Stub osascript and notify-send so the hook does not fire real
  # macOS notifications during tests (the previous implementation
  # leaked Notification Center entries).
  STUB_DIR=$(mktemp -d)
  for bin in osascript notify-send; do
    cat > "${STUB_DIR}/${bin}" <<EOF
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${STUB_DIR}/${bin}"
  done
  export PATH="${STUB_DIR}:${PATH}"
  # Use a unique session id per test so /tmp counter files don't collide.
  SID="budget-alert-test-$$-$RANDOM"
  COUNT_FILE="/tmp/claude-ops-${SID}.count"
  rm -f "$COUNT_FILE"
}

teardown() {
  rm -rf "$TMPHOME" "$STUB_DIR"
  rm -f "$COUNT_FILE"
}

posttool_payload() {
  jq -n --arg s "$SID" \
    '{hook_event_name:"PostToolUse",session_id:$s,tool_name:"Bash",tool_input:{command:"x"}}'
}

@test "happy path: increments per-session counter file" {
  payload=$(posttool_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "bash '$HOOK' < '$pfile'"
  [ "$status" -eq 0 ]

  run env HOME="$TMPHOME" bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]

  [ -f "$COUNT_FILE" ]
  COUNT=$(cat "$COUNT_FILE")
  [ "$COUNT" = "2" ]
}

@test "soft threshold: emits alert exactly at SOFT_LIMIT" {
  payload=$(posttool_payload)
  printf '4\n' > "$COUNT_FILE"
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  # Strip osascript / notify-send from PATH so the hook deterministically
  # falls back to its stderr alert form. That gives us something concrete
  # to grep for: a regression that silently stops emitting the soft alert
  # would leave stderr empty and fail this assertion.
  CLEAN=$(mktemp -d)
  for b in cat bash sh env jq; do
    real="$(command -v "$b" 2>/dev/null || true)"
    [[ -n "$real" ]] && ln -sf "$real" "$CLEAN/$b"
  done
  # SOFT_LIMIT=5 so the increment from 4→5 hits the threshold
  run env HOME="$TMPHOME" PATH="$CLEAN" \
    CLAUDE_BUDGET_SOFT_LIMIT=5 CLAUDE_BUDGET_HARD_LIMIT=99 \
    bash -c "bash '$HOOK' < '$pfile' 2>&1"
  rm -f "$pfile"; rm -rf "$CLEAN"
  [ "$status" -eq 0 ]
  [ "$(cat "$COUNT_FILE")" = "5" ]
  # The fallback alert prints to stderr ("[budget-alert] …Usage Notice…");
  # confirm the soft-threshold path actually fired.
  printf '%s' "$output" | grep -qi 'budget-alert.*Usage Notice'
}

@test "hard threshold: emits context block at HARD_LIMIT" {
  payload=$(posttool_payload)
  printf '6\n' > "$COUNT_FILE"
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  # HARD_LIMIT=7 so increment hits 7. Discard stderr so the
  # notify-send / fallback warning the hook prints there doesn't
  # land in $output and break jq parsing.
  run env HOME="$TMPHOME" CLAUDE_BUDGET_SOFT_LIMIT=2 CLAUDE_BUDGET_HARD_LIMIT=7 \
    bash -c "bash '$HOOK' < '$pfile' 2>/dev/null"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (.context | type == "string")' >/dev/null
  printf '%s' "$output" | jq -r '.context' | grep -q "High operation count"
}

@test "below threshold: exits 0 with no JSON output" {
  payload=$(posttool_payload)
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_BUDGET_SOFT_LIMIT=999 CLAUDE_BUDGET_HARD_LIMIT=999 bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
