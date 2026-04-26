#!/usr/bin/env bash
# Hook name:   ai-pr-description
# Event:       Stop
# Description: At session end, checks for commits on the current branch that
#              aren't in main. If ≥2 new commits exist, calls Haiku to draft a
#              PR description and writes it to /tmp/claude-pr-draft.md.
#              Outputs the file path as additionalContext. Non-blocking.
#
# Config (env vars):
#   ANTHROPIC_API_KEY   Required. If absent, hook skips silently.
#
# Install — add to .claude/settings.json:
#   { "hooks": { "Stop": [{ "hooks": [{ "type": "command",
#     "command": "/path/to/hooks/ai/ai-pr-description.sh" }] }] } }

set -euo pipefail

INPUT=$(cat)

# ── dependency checks ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null || ! command -v curl &>/dev/null; then exit 0; fi

ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$ANTHROPIC_API_KEY" ]]; then exit 0; fi

# ── check git repo ─────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then exit 0; fi
if ! git rev-parse --git-dir &>/dev/null 2>&1; then exit 0; fi

# ── check we're not on main ────────────────────────────────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi

# ── get commits ahead of main ──────────────────────────────────────────────────
BASE_BRANCH="main"
if ! git rev-parse --verify main &>/dev/null 2>&1; then
  BASE_BRANCH="master"
  if ! git rev-parse --verify master &>/dev/null 2>&1; then exit 0; fi
fi

COMMIT_LOG=$(git log "${BASE_BRANCH}..HEAD" --oneline 2>/dev/null || true)
if [[ -z "$COMMIT_LOG" ]]; then exit 0; fi

COMMIT_COUNT=$(wc -l <<< "$COMMIT_LOG" | tr -d ' ')
if (( COMMIT_COUNT < 2 )); then exit 0; fi

# ── gather diff stat for context ──────────────────────────────────────────────
DIFF_STAT=$(git diff "${BASE_BRANCH}...HEAD" --stat 2>/dev/null | tail -20 || true)

# ── call Haiku ─────────────────────────────────────────────────────────────────
INPUT_TEXT="Branch: ${CURRENT_BRANCH}

Commits (${COMMIT_COUNT}):
${COMMIT_LOG}

Diff stat:
${DIFF_STAT}"

PROMPT=$(jq -Rs \
  '"Write a concise GitHub PR description for these changes. Use this format:\n## Summary\n- bullet points (3 max)\n\n## Changes\n- bullet points of key changes\n\n## Test plan\n- [ ] checkboxes\n\nKeep it under 200 words.\n\n" + .' \
  <<< "$INPUT_TEXT")

RESPONSE=$(curl -sf https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{\"model\":\"claude-haiku-4-5\",\"max_tokens\":400,\"messages\":[{\"role\":\"user\",\"content\":$PROMPT}]}" \
  || true)

if [[ -z "$RESPONSE" ]]; then exit 0; fi

DRAFT=$(jq -r '.content[0].text // empty' <<< "$RESPONSE")
if [[ -z "$DRAFT" ]]; then exit 0; fi

# ── write draft file ───────────────────────────────────────────────────────────
DRAFT_FILE="/tmp/claude-pr-draft.md"
printf '# PR: %s\n\n%s\n' "$CURRENT_BRANCH" "$DRAFT" > "$DRAFT_FILE"

# ── output advisory context ────────────────────────────────────────────────────
jq -n --arg msg "PR description draft written to $DRAFT_FILE (${COMMIT_COUNT} commits on ${CURRENT_BRANCH})" \
  '{"additionalContext": $msg}'
