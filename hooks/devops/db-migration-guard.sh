#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   db-migration-guard
# Event:       PreToolUse (matcher: "Bash")
# Description: Blocks irreversible DB operations: DROP TABLE/DATABASE, TRUNCATE, unsafe DELETE FROM,
#              and migration rollback commands.
#
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/devops/db-migration-guard.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  exit 0
fi

COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT")

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only act on DB-related commands
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]])(psql|mysql|sqlite3|pg_dump|mongosh|mongo)[[:space:]]'; then
  # Also catch inline SQL piped or passed as -c/-e
  if ! echo "$COMMAND" | grep -qiE '(DROP[[:space:]]+(TABLE|DATABASE)|TRUNCATE|DELETE[[:space:]]+FROM)'; then
    # Check for migration rollback patterns
    if ! echo "$COMMAND" | grep -qE '(--down|rollback|migrate:down|db:rollback)'; then
      exit 0
    fi
  fi
fi

block() {
  local operation="$1"
  jq -n --arg op "$operation" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("Irreversible DB operation detected: " + $op + ". This operation cannot be undone. Aborting.")
    }
  }'
  exit 0
}

UPPER_CMD=$(echo "$COMMAND" | tr '[:lower:]' '[:upper:]')

# DROP TABLE
if echo "$UPPER_CMD" | grep -qE 'DROP[[:space:]]+TABLE'; then
  block "DROP TABLE"
fi

# DROP DATABASE
if echo "$UPPER_CMD" | grep -qE 'DROP[[:space:]]+DATABASE'; then
  block "DROP DATABASE"
fi

# DROP SCHEMA
if echo "$UPPER_CMD" | grep -qE 'DROP[[:space:]]+SCHEMA'; then
  block "DROP SCHEMA"
fi

# TRUNCATE
if echo "$UPPER_CMD" | grep -qE 'TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[A-Z_]'; then
  block "TRUNCATE"
fi

# DELETE FROM without WHERE clause
# Pattern: DELETE FROM <table> with no WHERE before ; or end-of-string
# Uses awk for macOS-safe multi-token check (no grep -P)
if echo "$UPPER_CMD" | grep -qE 'DELETE[[:space:]]+FROM[[:space:]]+[A-Z_0-9]+'; then
  # Check if WHERE is absent after the DELETE FROM clause
  HAS_WHERE=$(echo "$UPPER_CMD" | grep -c 'WHERE' || true)
  if [[ "$HAS_WHERE" -eq 0 ]]; then
    block "DELETE FROM without WHERE clause (full table delete)"
  fi
fi

# Migration rollback commands
if echo "$COMMAND" | grep -qE '(--down[[:space:]]|[[:space:]]rollback|migrate:down|db:rollback)'; then
  MATCHED=$(echo "$COMMAND" | grep -oE '(--down|rollback|migrate:down|db:rollback)' | head -1)
  block "migration rollback via '${MATCHED}'"
fi

exit 0
