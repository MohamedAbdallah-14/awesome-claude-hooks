#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/cost/budget-alert.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  # Use a unique session id per test so /tmp counter files don't collide.
  SID="budget-alert-test-$$-$RANDOM"
  COUNT_FILE="/tmp/claude-ops-${SID}.count"
  rm -f "$COUNT_FILE"
}

teardown() {
  rm -rf "$TMPHOME"
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
  # SOFT_LIMIT=5 so the increment from 4→5 hits the threshold
  run env HOME="$TMPHOME" CLAUDE_BUDGET_SOFT_LIMIT=5 CLAUDE_BUDGET_HARD_LIMIT=99 bash -c "bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ "$(cat "$COUNT_FILE")" = "5" ]
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
