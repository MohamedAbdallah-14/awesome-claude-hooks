#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Shared bats helpers for hook tests.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
export HOOKS_DIR="${REPO_ROOT}/hooks"

# Build a PreToolUse JSON payload for Write/Edit/Bash.
# Usage: pretool_payload <tool_name> <file_path_or_command> <content>
pretool_payload() {
  local tool="$1" arg="$2" content="${3:-}"
  case "$tool" in
    Write)
      jq -n --arg t "$tool" --arg p "$arg" --arg c "$content" \
        '{hook_event_name:"PreToolUse",session_id:"test",tool_name:$t,tool_input:{file_path:$p,content:$c}}'
      ;;
    Edit)
      jq -n --arg t "$tool" --arg p "$arg" --arg c "$content" \
        '{hook_event_name:"PreToolUse",session_id:"test",tool_name:$t,tool_input:{file_path:$p,old_string:"",new_string:$c}}'
      ;;
    Bash)
      jq -n --arg t "$tool" --arg cmd "$arg" \
        '{hook_event_name:"PreToolUse",session_id:"test",tool_name:$t,tool_input:{command:$cmd}}'
      ;;
    *)
      echo "unknown tool $tool" >&2
      return 1
      ;;
  esac
}

# Run a hook with a JSON payload on stdin via a tmpfile (avoids quoting hell).
# Sets bats $status, $output.
# Usage: run_hook <hook_path> <payload_json>
run_hook() {
  local hook="$1" payload="$2"
  local tmp
  tmp=$(mktemp)
  printf '%s' "$payload" > "$tmp"
  run bash -c "bash '$hook' < '$tmp'"
  rm -f "$tmp"
}

# Assert: hook returned a deny decision via PreToolUse hookSpecificOutput.
# Per the official Claude Code hooks contract: exit 0, with stdout JSON
# `{ hookSpecificOutput: { hookEventName, permissionDecision: "deny", ... } }`.
# Usage inside a @test: assert_blocked
assert_blocked() {
  [ "$status" -eq 0 ] || { echo "expected exit 0 (got $status). output: $output" >&2; return 1; }
  if ! printf '%s' "$output" | jq -e '
        .hookSpecificOutput.permissionDecision == "deny" and
        (.hookSpecificOutput.hookEventName == "PreToolUse")
      ' >/dev/null; then
    echo "expected hookSpecificOutput.permissionDecision=deny. output: $output" >&2
    return 1
  fi
}

# Build a PostToolUse JSON payload for Write/Edit/MultiEdit.
# Usage: posttool_payload <tool_name> <file_path> [content]
posttool_payload() {
  local tool="$1" path="$2" content="${3:-}"
  jq -n --arg t "$tool" --arg p "$path" --arg c "$content" \
    '{hook_event_name:"PostToolUse",session_id:"test",tool_name:$t,tool_input:{file_path:$p,content:$c},tool_response:{success:true}}'
}

# Assert: PostToolUse hook returned a block decision.
#
# Per the official Claude Code hooks contract
# (https://code.claude.com/docs/en/hooks), PostToolUse blocks use the
# top-level `decision: "block"` shape:
#
#   {
#     "decision": "block",
#     "reason": "...",
#     "hookSpecificOutput": {
#       "hookEventName": "PostToolUse",
#       "additionalContext": "..."
#     }
#   }
#
# A legacy `hookSpecificOutput.permissionDecision: "deny"` shape (mirroring
# PreToolUse) is also accepted here so older hooks in this repo still pass
# while we migrate them to the canonical contract.
# Usage inside a @test: assert_blocked_post
assert_blocked_post() {
  [ "$status" -eq 0 ] || { echo "expected exit 0 (got $status). output: $output" >&2; return 1; }
  if ! printf '%s' "$output" | jq -e '
        # Canonical contract shape.
        ( .decision == "block"
          and (.reason | type == "string")
          and (.hookSpecificOutput.hookEventName == "PostToolUse")
        )
        or
        # Legacy PreToolUse-style shape still emitted by some PostToolUse hooks.
        ( .hookSpecificOutput.permissionDecision == "deny"
          and (.hookSpecificOutput.hookEventName == "PostToolUse")
        )
      ' >/dev/null; then
    echo "expected PostToolUse block (decision=block + hookSpecificOutput.hookEventName=PostToolUse). output: $output" >&2
    return 1
  fi
}

# Assert: hook allowed the action (no decision JSON, exit 0, no stdout body).
assert_allowed() {
  [ "$status" -eq 0 ] || { echo "expected exit 0 (got $status). output: $output" >&2; return 1; }
}
