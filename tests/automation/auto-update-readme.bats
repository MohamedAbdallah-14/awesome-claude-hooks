#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="${HOOKS_DIR}/automation/auto-update-readme.sh"

setup() {
  TMPHOME=$(mktemp -d)
  export HOME="$TMPHOME"
  WORK=$(mktemp -d)
  cd "$WORK" || exit 1
}

teardown() {
  rm -rf "$TMPHOME" "$WORK"
}

posttool_payload() {
  local fp="$1"
  jq -n --arg p "$fp" \
    '{hook_event_name:"PostToolUse",session_id:"t",tool_name:"Write",tool_input:{file_path:$p}}'
}

@test "opt-in gate: disabled by default — README untouched" {
  echo '{"name":"p","version":"2.0.0"}' > "${WORK}/package.json"
  printf '# README\n\nversion: 1.0.0\n' > "${WORK}/README.md"
  payload=$(posttool_payload "${WORK}/package.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  grep -q "version: 1.0.0" "${WORK}/README.md"
}

@test "happy path: package.json bump rewrites README version line" {
  echo '{"name":"p","version":"2.0.0"}' > "${WORK}/package.json"
  printf '# README\n\nversion: 1.0.0\n' > "${WORK}/README.md"
  payload=$(posttool_payload "${WORK}/package.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_UPDATE_README=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  grep -q "version: 2.0.0" "${WORK}/README.md"
  ! grep -q "version: 1.0.0" "${WORK}/README.md"
}

@test "happy path: shields.io badge URL (badge/vX.Y.Z form) is bumped" {
  echo '{"name":"p","version":"3.4.5"}' > "${WORK}/package.json"
  # The hook's regex matches `badge/v?<digits>` — the "v" is optional but the
  # next char must be a digit. So `badge/v1.0.0-` works; `badge/version-1.0.0-`
  # does not (covered by the version: form instead).
  printf '# README\n\n![v](https://img.shields.io/badge/v1.0.0-blue)\n' > "${WORK}/README.md"
  payload=$(posttool_payload "${WORK}/package.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_UPDATE_README=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  grep -q "v3.4.5-" "${WORK}/README.md"
  ! grep -q "v1.0.0-" "${WORK}/README.md"
}

@test "silent skip: non-manifest file — exits 0 silently" {
  printf 'x' > "${WORK}/random.txt"
  payload=$(posttool_payload "${WORK}/random.txt")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_UPDATE_README=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent skip: README has no version references" {
  echo '{"name":"p","version":"2.0.0"}' > "${WORK}/package.json"
  printf '# README\n\nNo version mentioned.\n' > "${WORK}/README.md"
  payload=$(posttool_payload "${WORK}/package.json")
  pfile=$(mktemp); printf '%s' "$payload" > "$pfile"
  run env HOME="$TMPHOME" CLAUDE_AUTO_UPDATE_README=1 bash -c "cd '$WORK' && bash '$HOOK' < '$pfile'"
  rm -f "$pfile"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi "no version references\|skipping"
}
