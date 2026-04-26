#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   log-bash-history
# Event:       PostToolUse (matcher: "Bash")
# Description: Appends every Bash command Claude runs to a persistent history
#              log. Useful for auditing, debugging, and reproducing sessions.
#
#              Log format (pipe-delimited):
#                ISO_TIMESTAMP | session_id | COMMAND | EXIT_CODE
#
#              Exit code detection: if tool_response.stderr is non-empty and
#              stdout doesn't end with a zero-exit indicator, marks as FAIL.
#              This is heuristic — the hook payload doesn't carry a raw exit
#              code, so we infer from stderr presence.
#
#              Example:
#                2026-04-26T02:15:03+00:00 | abc123 | git status | 0
#                2026-04-26T02:15:04+00:00 | abc123 | rm -rf /oops | ERR
#
# Config (env vars):
#   CLAUDE_BASH_HISTORY_LOG   Override the default log path.
#                             Default: ~/.claude/bash-history.log
#
# Install — add to ~/.claude/settings.json (matcher targets Bash only):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/cost/log-bash-history.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[log-bash-history] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

HIST_LOG="${CLAUDE_BASH_HISTORY_LOG:-${HOME}/.claude/bash-history.log}"

# ── ensure log directory exists ───────────────────────────────────────────────

mkdir -p "$(dirname "$HIST_LOG")" 2>/dev/null || true

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id              // "unknown"')
COMMAND=$(printf '%s' "$INPUT"    | jq -r '.tool_input.command       // ""')
STDERR=$(printf '%s' "$INPUT"     | jq -r '.tool_response.stderr     // ""')
STDOUT=$(printf '%s' "$INPUT"     | jq -r '.tool_response.stdout     // ""')

# Skip if no command (shouldn't happen with Bash matcher, but be safe)
if [[ -z "$COMMAND" || "$COMMAND" == "null" ]]; then
  exit 0
fi

# ── infer exit code ───────────────────────────────────────────────────────────
# The hook payload doesn't expose a raw exit code. Heuristic:
#   - Non-empty stderr suggests failure (many tools write to stderr on error)
#   - stdout containing "Error:" / "error:" also flags failure
# We log "0" when stderr is empty, "ERR" otherwise. Not perfect; useful.

EXIT_CODE="0"
if [[ -n "$STDERR" && "$STDERR" != "null" && "$STDERR" != "" ]]; then
  EXIT_CODE="ERR"
elif printf '%s' "$STDOUT" | grep -qiE '^(error|fatal|exception):' 2>/dev/null; then
  EXIT_CODE="ERR"
fi

# ── sanitize command for log line ─────────────────────────────────────────────
# Collapse newlines to spaces; strip pipe characters to avoid log column splits

COMMAND_CLEAN=$(printf '%s' "$COMMAND" | tr '\n' ' ' | tr '|' '/')

# ── write log entry ───────────────────────────────────────────────────────────

printf '%s | %s | %s | %s\n' \
  "$TIMESTAMP" \
  "$SESSION_ID" \
  "$COMMAND_CLEAN" \
  "$EXIT_CODE" \
  >> "$HIST_LOG" 2>/dev/null || {
    echo "[log-bash-history] WARNING: could not write to ${HIST_LOG}" >&2
  }

exit 0
