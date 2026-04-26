#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   block-dangerous-bash
# Event:       PreToolUse (matcher: "Bash")
# Description: Blocks (or warns on) shell commands that could cause
#              catastrophic, irreversible damage to the system.
#
#              Patterns blocked:
#                - rm -rf / variants (rm -rf /, rm -rf /*, rm -rf ~)
#                - Fork bomb: :(){ :|:& };:
#                - Disk wipe: dd if=/dev/zero of=/dev/sd*|/dev/hd*|/dev/nvme*
#                - Filesystem format: mkfs.*
#                - Piped remote execution: curl|wget ... | bash/sh
#
# Config (env vars):
#   CLAUDE_DANGEROUS_BASH_WARN_ONLY=1   Emit a warning to stderr and allow the
#                                       command instead of blocking it.
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
#               "command": "/path/to/hooks/security/block-dangerous-bash.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[block-dangerous-bash] WARNING: jq not found — install it with: brew install jq" >&2
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

# ── pattern matching ──────────────────────────────────────────────────────────

# Returns label if matched, empty string otherwise
MATCHED_LABEL=""
MATCHED_WHY=""

check_pattern() {
  local label="$1"
  local why="$2"
  local regex="$3"
  if printf '%s' "$COMMAND" | grep -qE "$regex" 2>/dev/null; then
    MATCHED_LABEL="$label"
    MATCHED_WHY="$why"
    return 0
  fi
  return 1
}

# Pattern 1: rm -rf / or rm -rf /* or rm -rf ~  (order matters — most specific first)
check_pattern \
  "rm -rf filesystem root" \
  "Recursively force-deletes the entire filesystem or home directory." \
  'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)[[:space:]]+(--|[[:space:]]*)(/\*?|~/?' \
  2>/dev/null || true

# Simpler catch-all for rm -rf /
if [[ -z "$MATCHED_LABEL" ]]; then
  if printf '%s' "$COMMAND" | grep -qE 'rm[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*-[[:alnum:]]*r[[:alnum:]]*[[:space:]]+(/[[:space:]]*$|/\*|~/?)' 2>/dev/null || \
     printf '%s' "$COMMAND" | grep -qE 'rm[[:space:]]+-rf[[:space:]]+(/[[:space:]]*$|/\*|~/?)' 2>/dev/null || \
     printf '%s' "$COMMAND" | grep -qE 'rm[[:space:]]+-fr[[:space:]]+(/[[:space:]]*$|/\*|~/?)' 2>/dev/null; then
    MATCHED_LABEL="rm -rf filesystem root"
    MATCHED_WHY="Recursively force-deletes the entire filesystem or home directory."
  fi
fi

# Pattern 2: Fork bomb
if [[ -z "$MATCHED_LABEL" ]]; then
  if printf '%s' "$COMMAND" | grep -qF ':(){ :|:& };:' 2>/dev/null || \
     printf '%s' "$COMMAND" | grep -qE ':\(\)\{.*:\|:.*\}' 2>/dev/null; then
    MATCHED_LABEL="fork bomb"
    MATCHED_WHY="Spawns processes exponentially until the system runs out of resources and crashes."
  fi
fi

# Pattern 3: dd disk wipe
if [[ -z "$MATCHED_LABEL" ]]; then
  if printf '%s' "$COMMAND" | grep -qE 'dd[[:space:]].*if=/dev/zero[[:space:]].*of=/dev/(sd|hd|nvme|vd|xvd)' 2>/dev/null || \
     printf '%s' "$COMMAND" | grep -qE 'dd[[:space:]].*of=/dev/(sd|hd|nvme|vd|xvd)[a-z]' 2>/dev/null; then
    MATCHED_LABEL="dd disk wipe"
    MATCHED_WHY="Overwrites a raw block device with zeros, permanently destroying all data on that disk."
  fi
fi

# Pattern 4: mkfs — filesystem format
if [[ -z "$MATCHED_LABEL" ]]; then
  if printf '%s' "$COMMAND" | grep -qE 'mkfs\.[a-z0-9]+[[:space:]]' 2>/dev/null || \
     printf '%s' "$COMMAND" | grep -qE '^[[:space:]]*mkfs[[:space:]]' 2>/dev/null; then
    MATCHED_LABEL="mkfs filesystem format"
    MATCHED_WHY="Formats a partition or block device, erasing all data on it."
  fi
fi

# Pattern 5: piped remote execution (curl/wget | bash or sh)
if [[ -z "$MATCHED_LABEL" ]]; then
  if printf '%s' "$COMMAND" | grep -qE '(curl|wget)[[:space:]].*\|[[:space:]]*(bash|sh|zsh|fish)' 2>/dev/null || \
     printf '%s' "$COMMAND" | grep -qE '(curl|wget)[[:space:]].*\|[[:space:]]*sudo[[:space:]]*(bash|sh)' 2>/dev/null; then
    MATCHED_LABEL="piped remote code execution"
    MATCHED_WHY="Downloads and immediately executes arbitrary code from the internet without review. Inspect the script URL first."
  fi
fi

# ── decision ──────────────────────────────────────────────────────────────────

if [[ -n "$MATCHED_LABEL" ]]; then
  REASON="Dangerous command detected (${MATCHED_LABEL}): ${MATCHED_WHY}"

  if [[ "${CLAUDE_DANGEROUS_BASH_WARN_ONLY:-0}" == "1" ]]; then
    printf '[block-dangerous-bash] WARNING: %s\n' "$REASON" >&2
    exit 0
  else
    jq -n --arg reason "$REASON Set CLAUDE_DANGEROUS_BASH_WARN_ONLY=1 to downgrade to a warning." \
      '
    {
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }
    '
    exit 0
  fi
fi

exit 0
