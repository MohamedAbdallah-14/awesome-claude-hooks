#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   check-npm-audit
# Event:       PreToolUse (matcher: "Bash")
# Description: Intercepts npm install / yarn add / pnpm add commands and
#              reminds you to audit dependencies. In warn-only mode (default)
#              it prints the package name and the audit reminder to stdout and
#              allows the install to proceed. With CLAUDE_NPM_AUDIT_BLOCK=1 it
#              runs `npm audit` on the project before install and blocks if
#              critical vulnerabilities are found.
#
#              Recognized commands:
#                npm install <pkg>   npm i <pkg>
#                yarn add <pkg>
#                pnpm add <pkg>
#
# Config (env vars):
#   CLAUDE_NPM_AUDIT_BLOCK=1   Run npm audit before install and block if any
#                              critical vulnerabilities exist. Requires npm in PATH.
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
#               "command": "/path/to/hooks/security/check-npm-audit.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[check-npm-audit] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

if [[ -z "$COMMAND" || "$COMMAND" == "null" ]]; then
  exit 0
fi

# ── detect package install command ───────────────────────────────────────────

PACKAGE_NAME=""
PACKAGE_MANAGER=""

# npm install <pkg> or npm i <pkg>
if printf '%s' "$COMMAND" | grep -qE '(^|;|&&|\|\|)[[:space:]]*(npm[[:space:]]+(install|i)[[:space:]])'; then
  PACKAGE_MANAGER="npm"
  # Extract package name(s): everything after install/i that doesn't start with -
  PACKAGE_NAME=$(printf '%s' "$COMMAND" | \
    grep -oE 'npm[[:space:]]+(install|i)[[:space:]]+[^;&|]+' | \
    sed -E 's/npm[[:space:]]+(install|i)[[:space:]]+//' | \
    sed -E 's/[[:space:]]+-[a-zA-Z].*//' | \
    tr -s ' ' | head -1)
fi

# yarn add <pkg>
if [[ -z "$PACKAGE_MANAGER" ]] && printf '%s' "$COMMAND" | grep -qE '(^|;|&&|\|\|)[[:space:]]*(yarn[[:space:]]+add[[:space:]])'; then
  PACKAGE_MANAGER="yarn"
  PACKAGE_NAME=$(printf '%s' "$COMMAND" | \
    grep -oE 'yarn[[:space:]]+add[[:space:]]+[^;&|]+' | \
    sed -E 's/yarn[[:space:]]+add[[:space:]]+//' | \
    sed -E 's/[[:space:]]+-[a-zA-Z].*//' | \
    tr -s ' ' | head -1)
fi

# pnpm add <pkg>
if [[ -z "$PACKAGE_MANAGER" ]] && printf '%s' "$COMMAND" | grep -qE '(^|;|&&|\|\|)[[:space:]]*(pnpm[[:space:]]+add[[:space:]])'; then
  PACKAGE_MANAGER="pnpm"
  PACKAGE_NAME=$(printf '%s' "$COMMAND" | \
    grep -oE 'pnpm[[:space:]]+add[[:space:]]+[^;&|]+' | \
    sed -E 's/pnpm[[:space:]]+add[[:space:]]+//' | \
    sed -E 's/[[:space:]]+-[a-zA-Z].*//' | \
    tr -s ' ' | head -1)
fi

# Not an install command — pass through
if [[ -z "$PACKAGE_MANAGER" ]]; then
  exit 0
fi

# Trim whitespace
PACKAGE_NAME=$(printf '%s' "${PACKAGE_NAME:-}" | xargs 2>/dev/null || printf '%s' "${PACKAGE_NAME:-}")

# ── blocking mode: run npm audit ──────────────────────────────────────────────

if [[ "${CLAUDE_NPM_AUDIT_BLOCK:-0}" == "1" ]]; then
  if ! command -v npm &>/dev/null; then
    echo "[check-npm-audit] WARNING: CLAUDE_NPM_AUDIT_BLOCK=1 but npm not found in PATH — skipping audit check." >&2
    exit 0
  fi

  # Only run if package.json exists in the current directory
  if [[ ! -f "package.json" ]]; then
    # Warn but allow — new project scaffold scenario
    printf '[check-npm-audit] NOTE: No package.json found; skipping pre-install audit. Remember to run npm audit after install.\n'
    exit 0
  fi

  AUDIT_OUTPUT=$(npm audit --json 2>/dev/null || true)

  if [[ -n "$AUDIT_OUTPUT" ]]; then
    CRITICAL_COUNT=$(printf '%s' "$AUDIT_OUTPUT" | jq -r '.metadata.vulnerabilities.critical // 0' 2>/dev/null || echo 0)

    if [[ "$CRITICAL_COUNT" -gt 0 ]]; then
      jq -n \
        --arg pkg "${PACKAGE_NAME:-unknown}" \
        --arg count "$CRITICAL_COUNT" \
        --arg reason "Blocked: npm audit found ${CRITICAL_COUNT} critical vulnerability/vulnerabilities in the current project before adding '${PACKAGE_NAME:-unknown}'. Run 'npm audit' and resolve critical issues before installing new packages. Unset CLAUDE_NPM_AUDIT_BLOCK to downgrade to a warning." \
        '{"decision":"block","reason":$reason}'
      exit 2
    fi
  fi

  # Audit clean — allow with informational note
  printf '[check-npm-audit] npm audit clean. Proceeding with install of %s.\n' "${PACKAGE_NAME:-packages}"
  exit 0
fi

# ── warn-only mode (default) ──────────────────────────────────────────────────

printf '[check-npm-audit] Installing %s via %s. Remember to run `npm audit` afterwards to check for new vulnerabilities.\n' \
  "${PACKAGE_NAME:-package(s)}" \
  "$PACKAGE_MANAGER"

exit 0
