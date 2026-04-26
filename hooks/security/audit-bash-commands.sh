#!/usr/bin/env bash
# Hook name:   audit-bash-commands
# Event:       PostToolUse (matcher: "Bash")
# Description: Logs every bash command Claude executes to an audit log.
#              Useful for reviewing what the agent did in a session and for
#              incident analysis.
#
#              Log format (pipe-delimited):
#                ISO_TIMESTAMP | SESSION_ID | CMD | <first 200 chars of command> | exit_code
#
#              Example:
#                2026-04-26T02:17:44+00:00 | abc123 | CMD | npm install express | 0
#
#              Log is rotated (moved to bash-audit.log.1) when it exceeds 10 MB.
#
# Config (env vars):
#   CLAUDE_BASH_AUDIT_LOG   Override the default log path.
#                           Default: ~/.claude/bash-audit.log
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/security/audit-bash-commands.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[audit-bash-commands] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

LOG_FILE="${CLAUDE_BASH_AUDIT_LOG:-${HOME}/.claude/bash-audit.log}"
LOG_MAX_BYTES=10485760  # 10 MB

# ── ensure log directory exists ───────────────────────────────────────────────

LOG_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_DIR" 2>/dev/null || true

# ── log rotation ──────────────────────────────────────────────────────────────

if [[ -f "$LOG_FILE" ]]; then
  LOG_SIZE=0
  if command -v stat &>/dev/null; then
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
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

if [[ -z "$COMMAND" || "$COMMAND" == "null" ]]; then
  exit 0
fi

# Truncate to first 200 characters, collapse newlines to spaces
COMMAND_TRUNCATED=$(printf '%s' "$COMMAND" | tr '\n' ' ' | cut -c1-200)

# ── extract exit code from tool_response ─────────────────────────────────────

# Claude Code puts exit code in tool_response. The shape varies; try common
# paths. Fall back to "-" if not present (e.g. command timed out).
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '
  .tool_response.exit_code //
  .tool_response.exitCode //
  .tool_response.returncode //
  "-"
' 2>/dev/null || echo "-")

# Sanitize: keep only digits and "-"
EXIT_CODE=$(printf '%s' "$EXIT_CODE" | tr -cd '0-9-')
EXIT_CODE="${EXIT_CODE:--}"

# ── write log entry ───────────────────────────────────────────────────────────

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

printf '%s | %s | CMD | %s | %s\n' \
  "$TIMESTAMP" \
  "$SESSION_ID" \
  "$COMMAND_TRUNCATED" \
  "$EXIT_CODE" \
  >> "$LOG_FILE" 2>/dev/null || {
    echo "[audit-bash-commands] WARNING: could not write to log ${LOG_FILE}" >&2
  }

exit 0
