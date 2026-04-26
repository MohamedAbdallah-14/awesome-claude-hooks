#!/usr/bin/env bash
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
