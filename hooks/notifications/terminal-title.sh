#!/usr/bin/env bash
# Hook name:   terminal-title
# Event:       PreToolUse AND Stop
# Description: Updates the terminal window/tab title to reflect Claude Code's
#              current status in real time.
#              PreToolUse → "⚙ Claude: running <tool_name>..."
#              Stop       → "✅ Claude: done"
#
#              Works with: iTerm2, Terminal.app, tmux, xterm, and most other
#              terminals that support the ANSI OSC 0 escape sequence.
#              In tmux, updates the *window* title via tmux rename-window.
#
# Config: none required
#
# Install — add BOTH events to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "PreToolUse": [
#         {
#           "matcher": "",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/notifications/terminal-title.sh"
#             }
#           ]
#         }
#       ],
#       "Stop": [
#         {
#           "matcher": "",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/notifications/terminal-title.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  # No jq: fall back to a generic "Claude: active" title
  HOOK_EVENT="unknown"
  TOOL_NAME="tool"
else
  HOOK_EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "tool"' 2>/dev/null || echo "tool")
fi

# ── pick title ────────────────────────────────────────────────────────────────

case "$HOOK_EVENT" in
  PreToolUse)
    TITLE="⚙ Claude: running ${TOOL_NAME}..."
    ;;
  Stop|SubagentStop)
    TITLE="✅ Claude: done"
    ;;
  *)
    TITLE="Claude Code"
    ;;
esac

# ── set title ─────────────────────────────────────────────────────────────────

set_title() {
  local title="$1"

  # tmux: rename the current window directly
  if [[ -n "${TMUX:-}" ]] && command -v tmux &>/dev/null; then
    tmux rename-window "$title" 2>/dev/null || true
    # Also push the OSC sequence through so the outer terminal (if any) sees it
    # printf '\033]0;%s\007' "$title" inside tmux goes to tmux, not outer terminal.
    # The window rename above is sufficient for tmux users.
    return
  fi

  # Standard OSC 0 escape: sets both icon name and window title.
  # Works in xterm, iTerm2, Terminal.app, Ghostty, Warp, Alacritty, Kitty, etc.
  # Write to /dev/tty so it works even when stdout is redirected.
  # Use a subshell so a non-writable /dev/tty never propagates an error
  ( printf '\033]0;%s\007' "$title" > /dev/tty ) 2>/dev/null || \
  ( printf '\033]0;%s\007' "$title" ) 2>/dev/null || true
}

set_title "$TITLE"

exit 0
