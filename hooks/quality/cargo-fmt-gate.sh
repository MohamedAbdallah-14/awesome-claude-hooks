#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   cargo-fmt-gate
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .rs file, runs `cargo fmt --check` (or
#              falls back to `rustfmt --check <file>` if no Cargo.toml is in
#              cwd). Blocks the change with a deny decision when the file
#              would be reformatted, so Claude can rerun with rustfmt applied.
#
#              Matches: .rs
#
# Config (env vars):
#   CLAUDE_CARGO_FMT_GATE_SKIP=1   Skip this gate entirely (silent pass). Default: gate enforced.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Write|Edit|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/quality/cargo-fmt-gate.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── bypass switch ─────────────────────────────────────────────────────────────

if [[ "${CLAUDE_CARGO_FMT_GATE_SKIP:-0}" == "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[cargo-fmt-gate] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── extension filter ──────────────────────────────────────────────────────────

case "$FILE_PATH" in
  *.rs) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── tool selection ────────────────────────────────────────────────────────────

FMT_OUTPUT=""
FMT_EXIT=0

if [[ -f "Cargo.toml" ]] && command -v cargo &>/dev/null; then
  FMT_OUTPUT=$(cargo fmt --check 2>&1) || FMT_EXIT=$?
elif command -v rustfmt &>/dev/null; then
  FMT_OUTPUT=$(rustfmt --check "$FILE_PATH" 2>&1) || FMT_EXIT=$?
else
  # Neither cargo nor rustfmt available — silently skip so users without
  # a Rust toolchain aren't blocked.
  exit 0
fi

if [[ $FMT_EXIT -eq 0 ]]; then
  exit 0
fi

# ── emit deny decision ────────────────────────────────────────────────────────

REASON="cargo-fmt-gate: $FILE_PATH is not formatted to rustfmt rules.

$FMT_OUTPUT

Fix with: cargo fmt   (or: rustfmt $FILE_PATH)
Bypass once with: CLAUDE_CARGO_FMT_GATE_SKIP=1"

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 0
