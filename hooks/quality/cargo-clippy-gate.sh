#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   cargo-clippy-gate
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .rs file, runs `cargo clippy --quiet --
#              -D warnings` from the current working directory. Blocks the
#              change with a deny decision on any clippy warning or error.
#              Skips silently when there is no Cargo.toml in cwd or when
#              cargo isn't on PATH (so non-Rust projects pass through).
#
#              Matches: .rs
#
# Config (env vars):
#   CLAUDE_CARGO_CLIPPY_GATE_SKIP=1   Skip this gate entirely (silent pass). Default: gate enforced.
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
#               "command": "/path/to/hooks/quality/cargo-clippy-gate.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── bypass switch ─────────────────────────────────────────────────────────────

if [[ "${CLAUDE_CARGO_CLIPPY_GATE_SKIP:-0}" == "1" ]]; then
  exit 0
fi

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[cargo-clippy-gate] WARNING: jq not found — install it with: brew install jq" >&2
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

# ── skip when no Cargo.toml or no cargo binary ───────────────────────────────

if [[ ! -f "Cargo.toml" ]]; then
  exit 0
fi

if ! command -v cargo &>/dev/null; then
  exit 0
fi

# ── run clippy ────────────────────────────────────────────────────────────────

CLIPPY_OUTPUT=""
CLIPPY_EXIT=0
CLIPPY_OUTPUT=$(cargo clippy --quiet -- -D warnings 2>&1) || CLIPPY_EXIT=$?

if [[ $CLIPPY_EXIT -eq 0 ]]; then
  exit 0
fi

# ── emit deny decision ────────────────────────────────────────────────────────

REASON="cargo-clippy-gate: clippy reported issues after editing $FILE_PATH.

$CLIPPY_OUTPUT

Fix with: cargo clippy --fix   (or address each lint manually)
Bypass once with: CLAUDE_CARGO_CLIPPY_GATE_SKIP=1"

jq -n --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

exit 0
