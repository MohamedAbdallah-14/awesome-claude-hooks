#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/prompt/session-context-injector.sh"

prompt_payload() {
  local prompt="$1" cwd="$2"
  jq -n --arg p "$prompt" --arg c "$cwd" \
    '{hook_event_name:"UserPromptSubmit",session_id:"s",prompt:$p,cwd:$c}'
}

setup() {
  TMP_REPO=$(mktemp -d)
  (
    cd "$TMP_REPO"
    git init -q 2>/dev/null
    git config user.email t@t
    git config user.name t
    git checkout -q -b feature/login 2>/dev/null || true
    : > .keep
    git add .keep
    git commit -q -m "init" 2>/dev/null || true
  )
}

teardown() {
  rm -rf "$TMP_REPO"
}

@test "session-context-injector: adds branch prefix when in git repo" {
  payload=$(prompt_payload "fix the auth bug" "$TMP_REPO")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | startswith("[branch:")' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | contains("fix the auth bug")' >/dev/null
}

@test "session-context-injector: adds CLAUDE.md indicator when present" {
  : > "$TMP_REPO/CLAUDE.md"
  payload=$(prompt_payload "do thing" "$TMP_REPO")
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | contains("CLAUDE.md:yes")' >/dev/null
}

@test "session-context-injector: silent when prompt empty" {
  payload=$(jq -n '{hook_event_name:"UserPromptSubmit",prompt:"",cwd:"/tmp"}')
  run_hook "$HOOK" "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-context-injector: silent when neither branch nor CLAUDE.md applies" {
  NON_GIT=$(mktemp -d)
  payload=$(prompt_payload "hi" "$NON_GIT")
  run_hook "$HOOK" "$payload"
  rm -rf "$NON_GIT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
