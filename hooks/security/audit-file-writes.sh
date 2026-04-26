#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   audit-file-writes
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: Appends a structured log entry for every file write Claude
#              performs. Useful for reviewing what changed in a session and
#              for compliance/audit trails.
#
#              Log format (pipe-delimited):
#                ISO_TIMESTAMP | SESSION_ID | WRITE | file_path | bytes_written
#
#              Example:
#                2026-04-26T02:15:03+00:00 | abc123 | WRITE | /src/app.ts | 1842
#
#              Log is rotated (moved to audit.log.1) when it exceeds 10 MB.
#
# Config (env vars):
#   CLAUDE_AUDIT_LOG   Override the default log path.
#                      Default: ~/.claude/audit.log
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
#               "command": "/path/to/hooks/security/audit-file-writes.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[audit-file-writes] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

LOG_FILE="${CLAUDE_AUDIT_LOG:-${HOME}/.claude/audit.log}"
LOG_MAX_BYTES=10485760  # 10 MB

# ── ensure log directory exists ───────────────────────────────────────────────

LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR" 2>/dev/null || true

# ── log rotation ──────────────────────────────────────────────────────────────

if [[ -f "$LOG_FILE" ]]; then
  LOG_SIZE=0
  if command -v stat &>/dev/null; then
    # macOS stat vs GNU stat
    if stat -f%z "$LOG_FILE" &>/dev/null; then
      LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    else
      LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    fi
  fi
  if [[ "$LOG_SIZE" -gt "$LOG_MAX_BYTES" ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
  fi
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"')

# Resolve file_path from tool_input
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── byte count ────────────────────────────────────────────────────────────────

# Prefer actual file size on disk (most accurate after the write completed).
# Fall back to counting bytes in the content field if the file is inaccessible.
BYTES_WRITTEN="-"

if [[ -f "$FILE_PATH" ]]; then
  if command -v stat &>/dev/null; then
    if stat -f%z "$FILE_PATH" &>/dev/null; then
      BYTES_WRITTEN=$(stat -f%z "$FILE_PATH" 2>/dev/null || echo "-")
    else
      BYTES_WRITTEN=$(stat -c%s "$FILE_PATH" 2>/dev/null || echo "-")
    fi
  fi
else
  # File not on disk (e.g. remote or virtual path) — count content length
  CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // ""')
  if [[ -n "$CONTENT" ]]; then
    BYTES_WRITTEN=${#CONTENT}
  fi
fi

# ── write log entry ───────────────────────────────────────────────────────────

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

printf '%s | %s | WRITE | %s | %s\n' \
  "$TIMESTAMP" \
  "$SESSION_ID" \
  "$FILE_PATH" \
  "$BYTES_WRITTEN" \
  >> "$LOG_FILE" 2>/dev/null || {
    echo "[audit-file-writes] WARNING: could not write to log ${LOG_FILE}" >&2
  }

exit 0
