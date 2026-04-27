#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   log-tool-failures
# Event:       PostToolUseFailure
# Description: Append every failed tool call to a daily JSONL log
#              (~/.claude/tool-failures/YYYY-MM-DD.jsonl). One line per
#              failure with timestamp, session id, tool name, error,
#              duration, and the offending input. Observability only —
#              never blocks. Useful for forensics, flake detection,
#              and sharing reproducible failures with teammates.
#
# Config (env vars):
#   CLAUDE_TOOL_FAILURES_DIR   Override log directory.
#                              Default: ~/.claude/tool-failures
#   CLAUDE_LOG_TOOL_FAILURES_OFF=1   Disable this hook (bypass).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUseFailure": [
#         {
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/session/log-tool-failures.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "[log-tool-failures] WARNING: jq not found — install it (brew install jq / apt-get install jq)" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_LOG_TOOL_FAILURES_OFF:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

# ── target log path ───────────────────────────────────────────────────────────

LOG_DIR="${CLAUDE_TOOL_FAILURES_DIR:-${HOME}/.claude/tool-failures}"
mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).jsonl"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── extract structured fields ─────────────────────────────────────────────────
# Truncate large inputs/errors to keep the log scannable. Cap each field at 2 KB.

ENTRY=$(printf '%s' "$INPUT" | jq -c \
  --arg ts "$TIMESTAMP" \
  '{
    ts: $ts,
    session_id: (.session_id // ""),
    tool_name: (.tool_name // ""),
    duration_ms: (.duration_ms // 0),
    is_interrupt: (.is_interrupt // false),
    error: ((.error // "") | tostring | .[0:2048]),
    tool_input: (.tool_input // {} | tostring | .[0:2048])
  }' 2>/dev/null) || ENTRY=""

if [[ -z "$ENTRY" ]]; then
  exit 0
fi

# ── append (best-effort, never block) ─────────────────────────────────────────

printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true

exit 0
