#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   permission-denied-logger
# Event:       PermissionDenied
# Description: Append every denied tool call to an audit JSONL log
#              (~/.claude/permission-denials/YYYY-MM-DD.jsonl). One line
#              per denial with timestamp, session id, tool name, denial
#              reason, and the offending input. Compliance and security
#              teams use this to spot repeat patterns. Observability
#              only — never blocks, never sets `retry`.
#
# Config (env vars):
#   CLAUDE_PERM_DENIED_DIR         Override log directory.
#                                  Default: ~/.claude/permission-denials
#   CLAUDE_PERM_DENIED_LOG_OFF=1   Disable this hook (bypass).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PermissionDenied": [
#         {
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/security/permission-denied-logger.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "[permission-denied-logger] WARNING: jq not found — install it (brew install jq / apt-get install jq)" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_PERM_DENIED_LOG_OFF:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

# ── target log path ───────────────────────────────────────────────────────────

LOG_DIR="${CLAUDE_PERM_DENIED_DIR:-${HOME}/.claude/permission-denials}"
mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).jsonl"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── extract structured fields ─────────────────────────────────────────────────

ENTRY=$(printf '%s' "$INPUT" | jq -c \
  --arg ts "$TIMESTAMP" \
  '{
    ts: $ts,
    session_id: (.session_id // ""),
    tool_name: (.tool_name // ""),
    tool_use_id: (.tool_use_id // ""),
    denial_reason: ((.denial_reason // "") | tostring | .[0:1024]),
    tool_input: (.tool_input // {} | tostring | .[0:2048])
  }' 2>/dev/null) || ENTRY=""

if [[ -z "$ENTRY" ]]; then
  exit 0
fi

# ── append (best-effort, never block) ─────────────────────────────────────────

printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null || true

exit 0
