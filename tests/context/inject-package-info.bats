#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/context/inject-package-info.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

edit_payload() {
  local fp="$1"
  jq -n --arg p "$fp" \
    '{hook_event_name:"PreToolUse",session_id:"t",tool_name:"Edit",tool_input:{file_path:$p,old_string:"",new_string:""}}'
}

@test "happy path: package.json yields summary context" {
  cat > "${WORK}/package.json" <<'EOF'
{
  "name": "demo-pkg",
  "version": "1.2.3",
  "dependencies": { "lodash": "^4.0.0", "react": "^18.0.0" },
  "devDependencies": { "jest": "^29.0.0" }
}
EOF
  payload=$(edit_payload "${WORK}/package.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (.context | type == "string")' >/dev/null
  printf '%s' "$output" | jq -r '.context' | grep -q "demo-pkg"
  printf '%s' "$output" | jq -r '.context' | grep -q "lodash"
}

@test "happy path: requirements.txt yields entry count" {
  cat > "${WORK}/requirements.txt" <<'EOF'
flask==2.0.0
requests>=2.28
# a comment
pytest
EOF
  payload=$(edit_payload "${WORK}/requirements.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.context' | grep -qi "requirements.txt"
  printf '%s' "$output" | jq -r '.context' | grep -q "flask"
}

@test "silent skip: non-manifest file approves with no context" {
  echo "x" > "${WORK}/random.txt"
  payload=$(edit_payload "${WORK}/random.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (has("context") | not)' >/dev/null
}

@test "silent skip: package.json that does not exist approves" {
  payload=$(edit_payload "${WORK}/does-not-exist/package.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve" and (has("context") | not)' >/dev/null
}

@test "silent skip: empty stdin approves" {
  pfile=$(mktemp); printf '' > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "approve"' >/dev/null
}
