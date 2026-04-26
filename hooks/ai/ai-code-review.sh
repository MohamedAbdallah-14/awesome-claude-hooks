#!/usr/bin/env bash
# Hook name:   ai-code-review
# Event:       PostToolUse
# Matcher:     Write
# Description: After each file write, sends the content to Claude Haiku (~$0.001)
#              for a 2-sentence code review. Flags only security vulnerabilities,
#              off-by-one errors, or obvious bugs. Skips files >100 lines and
#              non-code file types. If clean, Haiku replies "LGTM" and the hook
#              stays silent.
#
# Config (env vars):
#   ANTHROPIC_API_KEY   Required. If absent, hook skips silently.
#
# Install — add to .claude/settings.json:
#   { "hooks": { "PostToolUse": [{ "matcher": "Write",
#     "hooks": [{ "type": "command",
#       "command": "/path/to/hooks/ai/ai-code-review.sh" }] }] } }

set -euo pipefail

INPUT=$(cat)

# ── dependency checks ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null; then exit 0; fi

# ── API key ────────────────────────────────────────────────────────────────────
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$ANTHROPIC_API_KEY" ]]; then exit 0; fi

# ── parse input ────────────────────────────────────────────────────────────────
FILE_PATH=$(jq -r '.tool_input.path // empty' <<< "$INPUT")
CONTENT=$(jq -r '.tool_input.content // empty' <<< "$INPUT")

if [[ -z "$FILE_PATH" || -z "$CONTENT" ]]; then exit 0; fi

# ── filter: code files only ────────────────────────────────────────────────────
EXT="${FILE_PATH##*.}"
case "$EXT" in
  sh|js|ts|py|go|dart|rb|rs) ;;
  *) exit 0 ;;
esac

# ── filter: skip large files ───────────────────────────────────────────────────
LINE_COUNT=$(wc -l <<< "$CONTENT" | tr -d ' ')
if (( LINE_COUNT > 100 )); then exit 0; fi

# ── call Haiku ─────────────────────────────────────────────────────────────────
PROMPT=$(jq -Rs --arg path "$FILE_PATH" \
  '"Review this code change in 2 sentences max. Flag ONLY: security vulnerabilities, off-by-one errors, or obvious bugs. If clean, reply with exactly: LGTM\n\nFile: " + $path + "\n\n" + .' \
  <<< "$CONTENT")

RESPONSE=$(curl -sf https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":300,\"messages\":[{\"role\":\"user\",\"content\":$PROMPT}]}" \
  || true)

if [[ -z "$RESPONSE" ]]; then exit 0; fi

TEXT=$(jq -r '.content[0].text // empty' <<< "$RESPONSE")

if [[ -z "$TEXT" || "$TEXT" == "LGTM" ]]; then exit 0; fi

# ── inject review as context ───────────────────────────────────────────────────
jq -n --arg msg "AI code review (${FILE_PATH##*/}): $TEXT" \
  '{"additionalContext": $msg}'
