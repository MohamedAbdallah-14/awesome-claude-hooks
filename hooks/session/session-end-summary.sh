#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   session-end-summary
# Event:       SessionEnd
# Description: On session termination, append a markdown digest of the
#              session to ~/.claude/sessions/YYYY-MM-DD.md. Captures:
#              session id, end reason (clear/resume/logout/...), cwd,
#              tool-call count, files touched (Write/Edit/MultiEdit
#              counts), and approximate duration. Strictly observability.
#
#              This is the SessionEnd companion to the existing
#              `session-summary` hook (which fires on Stop, the per-turn
#              event). Both can run side-by-side — Stop fires every turn,
#              SessionEnd fires once when the session terminates.
#
# Platforms: macos, linux, wsl. Pure jq + file-append; no platform-specific
#            dependencies. The duration math handles both BSD `date -j -f`
#            (macOS) and GNU `date -d` (linux/wsl) explicitly.
#
# Config (env vars):
#   CLAUDE_SESSIONS_DIR             Override sessions directory.
#                                   Default: ~/.claude/sessions
#   CLAUDE_SESSION_END_SUMMARY_OFF=1   Disable this hook (bypass).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "SessionEnd": [
#         {
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/session/session-end-summary.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "[session-end-summary] WARNING: jq not found — install it (brew install jq / apt-get install jq)" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_SESSION_END_SUMMARY_OFF:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

# Guard each jq call with `2>/dev/null || echo` so malformed JSON on stdin
# doesn't abort the hook under `set -euo pipefail`. SessionEnd is strictly
# observability — best-effort, always exit 0.
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
CWD="${CWD:-$PWD}"

# SessionEnd matchers per spec: clear, resume, logout, prompt_input_exit,
# bypass_permissions_disabled, other. Field name varies by version — accept
# both `reason` and `matcher`.
END_REASON=$(printf '%s' "$INPUT" | jq -r '.reason // .matcher // "unknown"' 2>/dev/null || echo "unknown")

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

# ── transcript-derived counts ─────────────────────────────────────────────────

TOOL_CALLS=0
WRITES=0
EDITS=0
BASHES=0
START_TS=""
DURATION_HUMAN="unknown"

if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  TOOL_CALLS=$(grep -c '"type":"tool_use"' "$TRANSCRIPT" 2>/dev/null || echo 0)
  WRITES=$(grep -c '"name":"Write"' "$TRANSCRIPT" 2>/dev/null || echo 0)
  EDITS=$(grep -cE '"name":"(Edit|MultiEdit)"' "$TRANSCRIPT" 2>/dev/null || echo 0)
  BASHES=$(grep -c '"name":"Bash"' "$TRANSCRIPT" 2>/dev/null || echo 0)

  # Best-effort start timestamp from first JSONL record.
  FIRST_LINE=$(head -n 1 "$TRANSCRIPT" 2>/dev/null || echo "")
  if [[ -n "$FIRST_LINE" ]]; then
    START_TS=$(printf '%s' "$FIRST_LINE" | jq -r '.timestamp // empty' 2>/dev/null || echo "")
  fi

  if [[ -n "$START_TS" ]]; then
    # Compute duration in a portable-ish way. macOS `date -j -f` differs
    # from GNU `date -d`; try both.
    START_EPOCH=""
    # Normalise for the BSD branch: strip optional fractional seconds
    # (`.999`) and a trailing `Z`. `${START_TS%.*}` alone leaves the `Z`
    # in place when no fractional part is present, which makes
    # `date -j -f "%Y-%m-%dT%H:%M:%S"` fail and silently leave duration
    # as "unknown" for the common `2026-04-27T10:30:45Z` form.
    START_TS_NORM="${START_TS%.*}"
    START_TS_NORM="${START_TS_NORM%Z}"
    if date -d "$START_TS" +%s >/dev/null 2>&1; then
      START_EPOCH=$(date -d "$START_TS" +%s)
    elif date -j -f "%Y-%m-%dT%H:%M:%S" "$START_TS_NORM" +%s >/dev/null 2>&1; then
      START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$START_TS_NORM" +%s)
    fi
    if [[ -n "$START_EPOCH" ]]; then
      NOW_EPOCH=$(date +%s)
      DELTA=$(( NOW_EPOCH - START_EPOCH ))
      if (( DELTA >= 0 )); then
        H=$(( DELTA / 3600 ))
        M=$(( (DELTA % 3600) / 60 ))
        S=$(( DELTA % 60 ))
        DURATION_HUMAN=$(printf '%dh%02dm%02ds' "$H" "$M" "$S")
      fi
    fi
  fi
fi

# ── write digest ──────────────────────────────────────────────────────────────

SESSIONS_DIR="${CLAUDE_SESSIONS_DIR:-${HOME}/.claude/sessions}"
mkdir -p "$SESSIONS_DIR"

LOG_FILE="${SESSIONS_DIR}/$(date +%Y-%m-%d).md"
END_TIME=$(date +%H:%M:%S)

{
  printf '\n### Session ended at %s — reason: `%s`\n' "$END_TIME" "$END_REASON"
  printf -- '- session id: `%s`\n' "${SESSION_ID:-unknown}"
  printf -- '- cwd: `%s`\n' "$CWD"
  printf -- '- duration: %s\n' "$DURATION_HUMAN"
  printf -- '- tool calls: %d (Write %d, Edit/MultiEdit %d, Bash %d)\n' \
    "$TOOL_CALLS" "$WRITES" "$EDITS" "$BASHES"
} >> "$LOG_FILE" 2>/dev/null || true

exit 0
