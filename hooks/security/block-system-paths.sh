#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   block-system-paths
# Event:       PreToolUse (matcher: "Write|Edit|Bash")
# Description: Blocks writes to OS system paths and dangerous shell commands
#              that target system directories.
#
#              For Write/Edit tools: rejects file_path under /etc, /usr, /bin,
#              /sbin, /boot, /sys, /proc, /lib, /lib64.
#
#              For Bash: rejects commands containing:
#                - redirect into /etc/  (e.g. echo x > /etc/hosts)
#                - rm -rf / variants
#                - chmod 777 /  (world-writable root)
#
# Config (env vars):
#   CLAUDE_ALLOWED_SYSTEM_PATHS   Colon-separated list of path prefixes that
#                                 are explicitly permitted despite matching the
#                                 blocklist. Example:
#                                   CLAUDE_ALLOWED_SYSTEM_PATHS=/etc/hosts:/usr/local
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "Write|Edit|Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/security/block-system-paths.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[block-system-paths] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

# ── helpers ───────────────────────────────────────────────────────────────────

# Returns 0 if $1 is in the CLAUDE_ALLOWED_SYSTEM_PATHS exception list
is_allowed_exception() {
  local target="$1"
  local exceptions="${CLAUDE_ALLOWED_SYSTEM_PATHS:-}"
  if [[ -z "$exceptions" ]]; then
    return 1
  fi
  IFS=':' read -ra PARTS <<< "$exceptions"
  for part in "${PARTS[@]}"; do
    if [[ "$target" == "$part"* ]]; then
      return 0
    fi
  done
  return 1
}

block_with_reason() {
  jq -n --arg reason "$1" '
    {
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }
    '
  exit 0
}

# ── file-write path check (Write / Edit / MultiEdit) ─────────────────────────

if [[ "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "MultiEdit" ]]; then
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

  if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
    exit 0
  fi

  # Normalize: collapse // and ensure absolute path comparison
  NORMALIZED=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$FILE_PATH" 2>/dev/null || printf '%s' "$FILE_PATH")

  BLOCKED_PREFIXES=(
    /etc
    /usr
    /bin
    /sbin
    /boot
    /sys
    /proc
    /lib
    /lib64
  )

  for prefix in "${BLOCKED_PREFIXES[@]}"; do
    if [[ "$NORMALIZED" == "$prefix" || "$NORMALIZED" == "$prefix/"* ]]; then
      if is_allowed_exception "$NORMALIZED"; then
        exit 0
      fi
      block_with_reason "Blocked: write to system path '${NORMALIZED}' is not allowed. System paths under ${prefix} are protected. Add the path to CLAUDE_ALLOWED_SYSTEM_PATHS to permit specific exceptions."
    fi
  done

  exit 0
fi

# ── bash command check ────────────────────────────────────────────────────────

if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')

  if [[ -z "$COMMAND" || "$COMMAND" == "null" ]]; then
    exit 0
  fi

  # Pattern 1: redirect into /etc/
  if printf '%s' "$COMMAND" | grep -qE '>[[:space:]]*/etc/'; then
    block_with_reason "Blocked: command attempts to write into /etc/ via shell redirect. This could corrupt system configuration. Modify system files manually if truly needed."
  fi

  # Pattern 2: rm -rf / variants (/, /*, ~, \$HOME at root level)
  if printf '%s' "$COMMAND" | grep -qE 'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+(--|[[:space:]]*)(/\*?|~/?[[:space:]]|"/"[[:space:]]|'"'"'/"'"'"'[[:space:]])'; then
    block_with_reason "Blocked: command contains a recursive forced deletion targeting root or home (rm -rf / or similar). This would destroy the filesystem."
  fi

  # Simpler additional check for rm -rf / (catches more variants)
  if printf '%s' "$COMMAND" | grep -qE 'rm[[:space:]].*-[rR].*[[:space:]]/[[:space:]]*$|rm[[:space:]].*-[rR].*[[:space:]]/"[[:space:]]*$'; then
    block_with_reason "Blocked: command appears to run rm -rf against the filesystem root."
  fi

  # Pattern 3: chmod 777 /  — world-writable root
  if printf '%s' "$COMMAND" | grep -qE 'chmod[[:space:]].*777[[:space:]]*/[[:space:]]*$|chmod[[:space:]].*777[[:space:]]*/[^a-zA-Z0-9]'; then
    block_with_reason "Blocked: command attempts to set world-writable permissions on the filesystem root (chmod 777 /). This is a critical security violation."
  fi

  exit 0
fi

exit 0
