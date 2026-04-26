#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   scan-sql-injection
# Event:       PreToolUse (matcher: "Write|Edit|MultiEdit")
# Description: Scans source files for SQL injection anti-patterns before they
#              are written. Only runs on .py, .js, .ts, .php, .rb, .java, .go
#              files. Emits a warning to stderr but allows the write (exit 0)
#              by default. Set CLAUDE_SQL_BLOCK=1 to make it blocking.
#
#              Patterns detected (string concatenation into SQL):
#                - Python f-string:   f"SELECT ... {var}"
#                - Python %format:    "SELECT ..." % var
#                - Python +:          "SELECT ..." + var
#                - JS/TS template:    `SELECT ... ${var}`
#                - JS/TS +:           "SELECT ..." + var
#                - PHP concatenation: "SELECT ..." . $var
#                - execute/query calls with direct concatenation
#
# Config (env vars):
#   CLAUDE_SQL_BLOCK=1   Block the write instead of warning (default: warn only).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Write|Edit|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/security/scan-sql-injection.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[scan-sql-injection] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── file type filter ──────────────────────────────────────────────────────────

BASENAME=$(basename "$FILE_PATH")
EXT="${BASENAME##*.}"

case "$EXT" in
  py|js|ts|php|rb|java|go) ;;
  *) exit 0 ;;
esac

# ── extract content ───────────────────────────────────────────────────────────

case "$TOOL_NAME" in
  Write)
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""')
    ;;
  Edit)
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""')
    ;;
  MultiEdit)
    CONTENT=$(printf '%s' "$INPUT" | jq -r '
      (.tool_input.edits // [] | map(.new_string // "") | join("\n"))
    ')
    ;;
  *)
    exit 0
    ;;
esac

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# ── SQL injection pattern matching ────────────────────────────────────────────

# Each entry: "LABEL@@REGEX"
# Using @@ as separator to avoid collision with | used in ERE alternation groups.
declare -a PATTERNS=(
  # Python f-string with SQL keyword
  "Python f-string SQL interpolation@@f[\"'](SELECT|INSERT|UPDATE|DELETE|DROP|UNION)[^\"']*\{"
  # Python %-format with SQL keyword
  "Python %-format SQL concatenation@@(SELECT|INSERT|UPDATE|DELETE|DROP|UNION)[^\"']*%[[:space:]]"
  # Python/Java/Go string + var concatenation after SQL keyword
  "SQL string concatenation (+)@@\"(SELECT|INSERT|UPDATE|DELETE|DROP|UNION)[^\"]*\"[[:space:]]*\+"
  # JavaScript template literal with SQL keyword
  "JS template literal SQL interpolation@@\`(SELECT|INSERT|UPDATE|DELETE|DROP|UNION)[^\`]*\$\{"
  # PHP string concatenation (dot operator)
  "PHP SQL concatenation@@\"(SELECT|INSERT|UPDATE|DELETE|DROP|UNION)[^\"]*\"[[:space:]]*\."
  # execute/query with concatenation — language agnostic
  "execute() with SQL concatenation@@\.execute[[:space:]]*\([[:space:]]*[\"'](SELECT|INSERT|UPDATE|DELETE)[^\"']*\"[[:space:]]*[\+\.]"
  "query() with SQL concatenation@@\.query[[:space:]]*\([[:space:]]*[\"'](SELECT|INSERT|UPDATE|DELETE)[^\"']*\"[[:space:]]*[\+\.]"
  # cursor.execute in Python with format string or % interpolation
  "cursor.execute with format string@@cursor\.execute[[:space:]]*\([[:space:]]*f[\"']"
  "cursor.execute with % interpolation@@cursor\.execute[[:space:]]*\([[:space:]]*[\"'][^\"']*%[[:space:]]"
)

MATCHED_LABELS=()

for entry in "${PATTERNS[@]}"; do
  label="${entry%%@@*}"
  regex="${entry##*@@}"
  if printf '%s' "$CONTENT" | grep -qE "$regex" 2>/dev/null; then
    MATCHED_LABELS+=("$label")
  fi
done

# ── decision ──────────────────────────────────────────────────────────────────

if [[ "${#MATCHED_LABELS[@]}" -gt 0 ]]; then
  MATCHED_LIST=$(printf ' - %s\n' "${MATCHED_LABELS[@]}")
  MESSAGE="[scan-sql-injection] SECURITY WARNING: potential SQL injection in ${FILE_PATH}
Matched patterns:
${MATCHED_LIST}
Use parameterized queries / prepared statements instead of string concatenation.
Reference: https://owasp.org/www-community/attacks/SQL_Injection"

  if [[ "${CLAUDE_SQL_BLOCK:-0}" == "1" ]]; then
    jq -n \
      --arg reason "Blocked: SQL injection risk detected in ${FILE_PATH}. Patterns matched: ${MATCHED_LABELS[*]}. Use parameterized queries. Set CLAUDE_SQL_BLOCK=0 to downgrade to warning." \
      '{"decision":"block","reason":$reason}'
    exit 2
  else
    printf '%s\n' "$MESSAGE" >&2
  fi
fi

exit 0
