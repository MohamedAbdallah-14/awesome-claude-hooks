#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   ai-security-scan
# Event:       PostToolUse
# Matcher:     Write
# Description: After each file write to .py/.js/.ts/.go files, asks Haiku to
#              scan for OWASP Top 10 vulnerabilities. Injects findings as
#              context only when issues are found. Scans first 50 lines max.
#
# Config (env vars):
#   ANTHROPIC_API_KEY        Required. If absent, hook skips silently.
#   CLAUDE_SKIP_AI_SECURITY  Set to 1 to disable this hook entirely.
#
# Install — add to .claude/settings.json:
#   { "hooks": { "PostToolUse": [{ "matcher": "Write",
#     "hooks": [{ "type": "command",
#       "command": "/path/to/hooks/ai/ai-security-scan.sh" }] }] } }

set -euo pipefail

INPUT=$(cat)

# ── kill switch ────────────────────────────────────────────────────────────────
if [[ "${CLAUDE_SKIP_AI_SECURITY:-}" == "1" ]]; then exit 0; fi

# ── dependency checks ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null; then exit 0; fi

ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$ANTHROPIC_API_KEY" ]]; then exit 0; fi

# ── parse input ────────────────────────────────────────────────────────────────
FILE_PATH=$(jq -r '.tool_input.path // empty' <<< "$INPUT")
CONTENT=$(jq -r '.tool_input.content // empty' <<< "$INPUT")

if [[ -z "$FILE_PATH" || -z "$CONTENT" ]]; then exit 0; fi

# ── filter: target extensions only ────────────────────────────────────────────
EXT="${FILE_PATH##*.}"
case "$EXT" in
  py|js|ts|go) ;;
  *) exit 0 ;;
esac

# ── trim to first 50 lines ─────────────────────────────────────────────────────
TRIMMED=$(head -50 <<< "$CONTENT")

# ── call Haiku ─────────────────────────────────────────────────────────────────
PROMPT=$(jq -Rs --arg path "$FILE_PATH" \
  '"Scan this code for OWASP Top 10 vulnerabilities only. If none found, reply: CLEAN. Otherwise list findings as: VULN_TYPE: line_hint (one per line, max 5).\n\nFile: " + $path + "\n\n" + .' \
  <<< "$TRIMMED")

RESPONSE=$(curl -sf https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":300,\"messages\":[{\"role\":\"user\",\"content\":$PROMPT}]}" \
  || true)

if [[ -z "$RESPONSE" ]]; then exit 0; fi

TEXT=$(jq -r '.content[0].text // empty' <<< "$RESPONSE" | tr -d '\r')

if [[ -z "$TEXT" || "$TEXT" == "CLEAN" ]]; then exit 0; fi

# ── inject findings as context ─────────────────────────────────────────────────
jq -n --arg msg "Security scan (${FILE_PATH##*/}): $TEXT" \
  '{"additionalContext": $msg}'
