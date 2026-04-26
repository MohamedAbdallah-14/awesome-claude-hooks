#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   log-tool-usage
# Event:       PostToolUse
# Description: Appends a structured CSV entry for every tool call Claude makes.
#              Gives you a full audit trail of everything Claude touched across
#              all sessions. Rotate-safe: moves to usage.csv.1 when >5 MB.
#
#              CSV columns:
#                ISO_TIMESTAMP, session_id, tool_name, file_path_or_command
#
#              - file_path: tool_input.file_path if present
#              - command:   first 80 chars of tool_input.command for Bash calls
#              - empty string for tools with neither
#
#              Note: duration_ms is not available from the hook payload.
#              Log each call with its timestamp; diff adjacent lines offline
#              to compute elapsed time between calls.
#
# Config (env vars):
#   CLAUDE_USAGE_LOG   Override the default log path.
#                      Default: ~/.claude/usage.csv
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": ".*",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/cost/log-tool-usage.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[log-tool-usage] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

LOG_FILE="${CLAUDE_USAGE_LOG:-${HOME}/.claude/usage.csv}"
LOG_MAX_BYTES=5242880  # 5 MB

# ── ensure log directory exists ───────────────────────────────────────────────

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# ── log rotation ──────────────────────────────────────────────────────────────

if [[ -f "$LOG_FILE" ]]; then
  LOG_SIZE=0
  if stat -f%z "$LOG_FILE" &>/dev/null 2>&1; then
    LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
  elif stat -c%s "$LOG_FILE" &>/dev/null 2>&1; then
    LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  fi
  if [[ "$LOG_SIZE" -gt "$LOG_MAX_BYTES" ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
  fi
fi

# ── write CSV header if file is new ──────────────────────────────────────────

if [[ ! -f "$LOG_FILE" ]]; then
  printf 'timestamp,session_id,tool_name,context\n' >> "$LOG_FILE" 2>/dev/null || true
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')
TOOL_NAME=$(printf '%s' "$INPUT"  | jq -r '.tool_name  // "unknown"')

# Resolve the most useful context field for this tool
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
COMMAND=$(printf '%s' "$INPUT"   | jq -r '.tool_input.command   // ""')

if [[ -n "$FILE_PATH" && "$FILE_PATH" != "null" ]]; then
  CONTEXT="$FILE_PATH"
elif [[ -n "$COMMAND" && "$COMMAND" != "null" ]]; then
  # Trim to 80 chars; collapse newlines
  CONTEXT=$(printf '%s' "$COMMAND" | tr '\n' ' ' | cut -c1-80)
else
  CONTEXT=""
fi

# CSV-escape: wrap context in double-quotes, escape internal quotes
CONTEXT_ESCAPED=$(printf '%s' "$CONTEXT" | sed 's/"/""/g')

# ── write log entry ───────────────────────────────────────────────────────────

printf '"%s","%s","%s","%s"\n' \
  "$TIMESTAMP" \
  "$SESSION_ID" \
  "$TOOL_NAME" \
  "$CONTEXT_ESCAPED" \
  >> "$LOG_FILE" 2>/dev/null || {
    echo "[log-tool-usage] WARNING: could not write to ${LOG_FILE}" >&2
  }

exit 0
