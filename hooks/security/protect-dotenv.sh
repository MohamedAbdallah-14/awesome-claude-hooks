#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   protect-dotenv
# Event:       PreToolUse (matcher: "Write|Edit|MultiEdit")
# Description: Blocks writes to .env files to prevent accidental overwriting
#              of environment variable files that typically hold secrets.
#
#              Matches filenames like:
#                .env  .env.local  .env.production  .env.development
#                .env.test  .env.staging  any path ending in *.env
#                e.g. config/database.env
#
# Config (env vars):
#   CLAUDE_ALLOW_ENV_WRITES=1   Disable blocking (e.g. scaffolding a new project).
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
#               "command": "/path/to/hooks/security/protect-dotenv.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[protect-dotenv] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_ALLOW_ENV_WRITES:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── path matching ─────────────────────────────────────────────────────────────

# Extract the basename for matching
BASENAME=$(basename "$FILE_PATH")

IS_ENV_FILE=0

# Exact name: .env
if [[ "$BASENAME" == ".env" ]]; then
  IS_ENV_FILE=1
fi

# .env.* variants: .env.local, .env.production, .env.development, .env.test, etc.
# Allowlist non-secret companions: .env.example, .env.sample, .env.template, .env.dist
if [[ "$BASENAME" =~ ^\.env\. ]] \
   && ! [[ "$BASENAME" =~ ^\.env\.(example|sample|template|dist)$ ]]; then
  IS_ENV_FILE=1
fi

# *.env suffix: database.env, config.env, etc.
if [[ "$BASENAME" =~ \.env$ ]]; then
  IS_ENV_FILE=1
fi

# ── decision ──────────────────────────────────────────────────────────────────

if [[ "$IS_ENV_FILE" == "1" ]]; then
  jq -n \
    --arg path "$FILE_PATH" \
    --arg reason "Blocked: write to env file '${FILE_PATH}' is not allowed. Env files typically contain secrets and should be managed manually. Set CLAUDE_ALLOW_ENV_WRITES=1 to override." \
    '{"decision":"block","reason":$reason}'
  exit 2
fi

exit 0
