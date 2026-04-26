#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
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
# bash 3.2 compatible — defers per-key counting to awk so we don't need
# associative arrays.

TOTAL_CALLS=0

if [[ -f "$USAGE_LOG" ]]; then
  TOTAL_CALLS=$(awk -F, -v today="$TODAY" '
    NR==1 { next }                              # header
    {
      ts=$1; gsub(/"/,"",ts)
      if (index(ts, today) == 1) c++
    }
    END { print c+0 }
  ' "$USAGE_LOG")
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

# ── build top-5 tools / files ─────────────────────────────────────────────────
# bash 3.2 compatible — awk does the counting then sort + head + format.

TOP_TOOLS=""
TOP_FILES=""

if [[ -f "$USAGE_LOG" ]]; then
  TOP_TOOLS=$(awk -F, -v today="$TODAY" '
    NR==1 { next }
    {
      ts=$1; tool=$3; gsub(/"/,"",ts); gsub(/"/,"",tool)
      if (index(ts, today) == 1 && tool != "") tools[tool]++
    }
    END { for (t in tools) printf "%d %s\n", tools[t], t }
  ' "$USAGE_LOG" | sort -rn | head -5 | awk '{printf "| %-20s | %5d |\n", $2, $1}')

  TOP_FILES=$(awk -F, -v today="$TODAY" '
    NR==1 { next }
    {
      ts=$1; ctx=$4; gsub(/"/,"",ts); gsub(/"/,"",ctx)
      if (index(ts, today) == 1 && substr(ctx, 1, 1) == "/") files[ctx]++
    }
    END { for (f in files) printf "%d %s\n", files[f], f }
  ' "$USAGE_LOG" | sort -rn | head -5 | awk '{printf "| %-50s | %5d |\n", $2, $1}')
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
