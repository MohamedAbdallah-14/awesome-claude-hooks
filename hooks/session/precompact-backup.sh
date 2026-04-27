#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   precompact-backup
# Event:       PreCompact
# Description: Backs up the full transcript before Claude compacts it.
#              Writes a timestamped file so previous turns stay recoverable.
#
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreCompact": [
#         {
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/session/precompact-backup.sh"
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

TRANSCRIPT=$(jq -r '.transcript_path // empty' <<< "$INPUT")

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

BACKUP_DIR="$HOME/.claude/compacted"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
DEST="${BACKUP_DIR}/${TIMESTAMP}.json"

cp "$TRANSCRIPT" "$DEST"
