#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/notifications/terminal-title.sh"

@test "terminal-title: PreToolUse path exits 0 with no JSON output" {
  payload=$(jq -n '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"ls"}}')
  # /dev/tty likely unavailable under bats; the hook handles that gracefully
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}

@test "terminal-title: Stop path exits 0" {
  payload=$(jq -n '{hook_event_name:"Stop",session_id:"x"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}

@test "terminal-title: SubagentStop path exits 0" {
  payload=$(jq -n '{hook_event_name:"SubagentStop",session_id:"x"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}

@test "terminal-title: tmux mode renames window via tmux binary" {
  STUB_DIR=$(mktemp -d)
  STUB_LOG="${STUB_DIR}/tmux.log"
  cat > "${STUB_DIR}/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
exit 0
EOF
  chmod +x "${STUB_DIR}/tmux"
  payload=$(jq -n '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{}}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env TMUX="/tmp/tmux-1000/default,1234,0" \
    PATH="${STUB_DIR}:${PATH}" STUB_LOG="$STUB_LOG" \
    bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -f "$STUB_LOG" ]
  grep -q "rename-window" "$STUB_LOG"
  grep -q "Edit" "$STUB_LOG"
  rm -rf "$STUB_DIR"
}

@test "terminal-title: handles unknown event without error" {
  payload=$(jq -n '{hook_event_name:"WeirdEvent"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
}
