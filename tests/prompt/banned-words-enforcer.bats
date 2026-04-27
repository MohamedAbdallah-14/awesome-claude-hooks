#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/prompt/banned-words-enforcer.sh"

prompt_payload() {
  local prompt="$1"
  jq -n --arg p "$prompt" '{hook_event_name:"UserPromptSubmit",session_id:"s",prompt:$p}'
}

setup() {
  TMP_HOME=$(mktemp -d)
  mkdir -p "${TMP_HOME}/.claude"
}

teardown() {
  rm -rf "$TMP_HOME"
}

@test "banned-words-enforcer: silent when banned-words.txt does not exist" {
  payload=$(prompt_payload "let's leverage synergy")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "banned-words-enforcer: silent when prompt has no banned words" {
  printf 'leverage\nsynergy\n' > "${TMP_HOME}/.claude/banned-words.txt"
  payload=$(prompt_payload "please refactor this function")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "banned-words-enforcer: appends reminder via updatedPrompt when match found" {
  printf 'leverage\nsynergy\n' > "${TMP_HOME}/.claude/banned-words.txt"
  payload=$(prompt_payload "we should leverage this library")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | contains("Avoid these words")' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | contains("leverage")' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | startswith("we should leverage")' >/dev/null
}

@test "banned-words-enforcer: matches case-insensitively" {
  printf 'utilize\n' > "${TMP_HOME}/.claude/banned-words.txt"
  payload=$(prompt_payload "Please UTILIZE the helper.")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt | contains("Avoid")' >/dev/null
}

@test "banned-words-enforcer: ignores comments and blank lines" {
  printf '# this is a comment\n\nleverage\n' > "${TMP_HOME}/.claude/banned-words.txt"
  payload=$(prompt_payload "we discuss leverage")
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.updatedPrompt' >/dev/null
}

@test "banned-words-enforcer: silent when prompt is empty" {
  printf 'leverage\n' > "${TMP_HOME}/.claude/banned-words.txt"
  payload=$(jq -n '{hook_event_name:"UserPromptSubmit",prompt:""}')
  tmp=$(mktemp); printf '%s' "$payload" > "$tmp"
  run env HOME="$TMP_HOME" bash -c "bash '$HOOK' < '$tmp'"
  rm -f "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
