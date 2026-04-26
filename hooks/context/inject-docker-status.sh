#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   inject-docker-status
# Event:       PreToolUse
# Matcher:     Bash
# Description: When Claude is about to run a command that involves Docker,
#              inject the current state of running containers so Claude
#              knows what's already up before issuing docker run / up / exec.
#
#              Triggers on commands containing: docker, docker-compose,
#              docker compose.
#
#              Gracefully no-ops if Docker is not installed or the daemon
#              is not running (returns approve with no context rather than
#              blocking or erroring).
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
#               "command": "/path/to/hooks/context/inject-docker-status.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────

approve() { printf '{"decision":"approve"}\n'; exit 0; }

approve_with_context() {
  local ctx="$1"
  jq -n --arg c "$ctx" '{"decision":"approve","context":$c}'
  exit 0
}

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  approve
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  approve
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [[ -z "$COMMAND" ]]; then
  approve
fi

# ── check if command is docker-related ───────────────────────────────────────

if ! printf '%s' "$COMMAND" | grep -qE '(^|[[:space:];|&])(docker(-compose)?|docker compose)([[:space:]]|$)'; then
  approve
fi

# ── check Docker is installed ─────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
  approve_with_context "Docker is not installed on this system."
fi

# ── check Docker daemon is running ────────────────────────────────────────────

if ! docker info &>/dev/null 2>&1; then
  approve_with_context "Docker is installed but the daemon is not running. Start it before running Docker commands."
fi

# ── get running containers ────────────────────────────────────────────────────

DOCKER_PS=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true)

# Also pull in any compose projects that are partially up
COMPOSE_PROJECTS=""
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
  COMPOSE_PROJECTS=$(docker compose ls 2>/dev/null | tail -n +2 || true)
fi

# ── format context ────────────────────────────────────────────────────────────

if [[ -z "$DOCKER_PS" ]] || [[ "$DOCKER_PS" == "NAMES"* && $(printf '%s' "$DOCKER_PS" | wc -l) -le 1 ]]; then
  # Only header row — no containers running
  CONTAINER_SECTION="No containers currently running."
else
  CONTAINER_SECTION="\`\`\`\n${DOCKER_PS}\n\`\`\`"
fi

if [[ -n "$COMPOSE_PROJECTS" ]]; then
  COMPOSE_SECTION="\n\n**Compose projects:**\n\`\`\`\n${COMPOSE_PROJECTS}\n\`\`\`"
else
  COMPOSE_SECTION=""
fi

CONTEXT="Running Docker containers:\n\n${CONTAINER_SECTION}${COMPOSE_SECTION}"

approve_with_context "$CONTEXT"
