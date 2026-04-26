#!/usr/bin/env bash
# Hook name:   daily-usage-report
# Event:       Stop
# Description: Generates a brief Markdown summary of today's Claude usage once
#              per calendar day. Reads ~/.claude/usage.csv (from log-tool-usage)
#              and ~/.claude/sessions.log (from session-timer) to produce:
#
#                - Total sessions today
#                - Total tool calls today
#                - Top 5 most-used tools
#                - Total time spent (sum of session durations)
#                - Files most often edited (top 5 Write/Edit paths)
#
#              Output: ~/.claude/reports/YYYY-MM-DD.md
#              Guard:  /tmp/claude-daily-report-YYYY-MM-DD.done (one run/day)
#
# Config (env vars):
#   CLAUDE_DAILY_REPORT_PATH   Override the output directory.
#                              Default: ~/.claude/reports
#
# Install — add to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "hooks": [{ "type": "command", "command": "/path/to/hooks/cost/daily-usage-report.sh" }]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[daily-usage-report] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

REPORT_DIR="${CLAUDE_DAILY_REPORT_PATH:-${HOME}/.claude/reports}"
USAGE_LOG="${CLAUDE_USAGE_LOG:-${HOME}/.claude/usage.csv}"
SESSION_LOG="${CLAUDE_SESSION_LOG:-${HOME}/.claude/sessions.log}"

TODAY=$(date -u +"%Y-%m-%d")
DONE_FILE="/tmp/claude-daily-report-${TODAY}.done"

# ── guard: only run once per day ─────────────────────────────────────────────

if [[ -f "$DONE_FILE" ]]; then
  exit 0
fi

# ── ensure output directory exists ───────────────────────────────────────────

mkdir -p "$REPORT_DIR" 2>/dev/null || true

# ── helpers ───────────────────────────────────────────────────────────────────

# Seconds → "Xh Ym Zs"
format_duration() {
  local secs=$1
  local h=$(( secs / 3600 ))
  local m=$(( (secs % 3600) / 60 ))
  local s=$(( secs % 60 ))
  if [[ $h -gt 0 ]]; then
    printf '%dh %dm %ds' "$h" "$m" "$s"
  elif [[ $m -gt 0 ]]; then
    printf '%dm %ds' "$m" "$s"
  else
    printf '%ds' "$s"
  fi
}

# ── parse usage.csv ───────────────────────────────────────────────────────────

TOTAL_CALLS=0
declare -A TOOL_COUNTS
declare -A FILE_COUNTS

if [[ -f "$USAGE_LOG" ]]; then
  while IFS=',' read -r ts sid tool ctx; do
    # Strip surrounding quotes
    ts=$(printf '%s' "$ts"   | tr -d '"')
    tool=$(printf '%s' "$tool" | tr -d '"')
    ctx=$(printf '%s' "$ctx"   | tr -d '"')

    # Skip header line
    [[ "$ts" == "timestamp" ]] && continue

    # Filter to today
    [[ "$ts" != "${TODAY}"* ]] && continue

    TOTAL_CALLS=$(( TOTAL_CALLS + 1 ))
    TOOL_COUNTS["$tool"]=$(( ${TOOL_COUNTS["$tool"]:-0} + 1 ))

    # Track edited files (ctx is a file path when it starts with /)
    if [[ "$ctx" == /* ]]; then
      FILE_COUNTS["$ctx"]=$(( ${FILE_COUNTS["$ctx"]:-0} + 1 ))
    fi
  done < "$USAGE_LOG"
fi

# ── parse sessions.log ────────────────────────────────────────────────────────

TOTAL_SESSIONS=0
TOTAL_SECS=0

if [[ -f "$SESSION_LOG" ]]; then
  while IFS='|' read -r date sid duration count; do
    date=$(printf '%s' "$date" | xargs)
    [[ "$date" != "$TODAY" ]] && continue
    TOTAL_SESSIONS=$(( TOTAL_SESSIONS + 1 ))
    dur=$(printf '%s' "$duration" | xargs)
    TOTAL_SECS=$(( TOTAL_SECS + dur ))
  done < "$SESSION_LOG"
fi

# ── build top-5 tools ─────────────────────────────────────────────────────────

TOP_TOOLS=""
if [[ ${#TOOL_COUNTS[@]} -gt 0 ]]; then
  TOP_TOOLS=$(
    for tool in "${!TOOL_COUNTS[@]}"; do
      printf '%d %s\n' "${TOOL_COUNTS[$tool]}" "$tool"
    done | sort -rn | head -5 | awk '{printf "| %-20s | %5d |\n", $2, $1}'
  )
fi

# ── build top-5 files ─────────────────────────────────────────────────────────

TOP_FILES=""
if [[ ${#FILE_COUNTS[@]} -gt 0 ]]; then
  TOP_FILES=$(
    for f in "${!FILE_COUNTS[@]}"; do
      printf '%d %s\n' "${FILE_COUNTS[$f]}" "$f"
    done | sort -rn | head -5 | awk '{printf "| %-50s | %5d |\n", $2, $1}'
  )
fi

# ── write report ──────────────────────────────────────────────────────────────

REPORT_FILE="${REPORT_DIR}/${TODAY}.md"
TOTAL_TIME=$(format_duration "$TOTAL_SECS")

{
  printf '# Claude Usage Report — %s\n\n' "$TODAY"
  printf '_Generated automatically by daily-usage-report hook_\n\n'
  printf '## Summary\n\n'
  printf '| Metric            | Value |\n'
  printf '|-------------------|-------|\n'
  printf '| Sessions today    | %d |\n' "$TOTAL_SESSIONS"
  printf '| Total tool calls  | %d |\n' "$TOTAL_CALLS"
  printf '| Total time        | %s |\n\n' "$TOTAL_TIME"

  printf '## Top Tools\n\n'
  if [[ -n "$TOP_TOOLS" ]]; then
    printf '| Tool                 | Calls |\n'
    printf '|----------------------|-------|\n'
    printf '%s\n' "$TOP_TOOLS"
  else
    printf '_No tool calls recorded today._\n'
  fi

  printf '\n## Most Edited Files\n\n'
  if [[ -n "$TOP_FILES" ]]; then
    printf '| File                                               | Times |\n'
    printf '|----------------------------------------------------|-------|\n'
    printf '%s\n' "$TOP_FILES"
  else
    printf '_No file edits recorded today._\n'
  fi

  printf '\n---\n'
  printf '_Data sources: `%s`, `%s`_\n' "$USAGE_LOG" "$SESSION_LOG"
} > "$REPORT_FILE" 2>/dev/null || {
  echo "[daily-usage-report] WARNING: could not write report to ${REPORT_FILE}" >&2
  exit 0
}

# Mark done for today
touch "$DONE_FILE" 2>/dev/null || true

exit 0
