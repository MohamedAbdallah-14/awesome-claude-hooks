#!/usr/bin/env bash
# Hook name:   sound-error
# Event:       PostToolUse
# Description: Plays an error sound when a tool exits with a non-zero exit code
#              or when the tool response stderr contains the word "Error".
#              macOS: uses afplay with Basso.aiff.
#              Linux: tries paplay then aplay with a system alert sound.
#
# Config (env vars):
#   CLAUDE_SOUND_ERROR   Override the sound file path.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/notifications/sound-error.sh"
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
  echo "[sound-error] WARNING: jq not found — cannot inspect tool response" >&2
  exit 0
fi

# Check exit_code field (present for Bash tool responses)
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // 0' 2>/dev/null || echo "0")

# Check stderr for "Error" as a secondary signal
STDERR_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // ""' 2>/dev/null || true)

IS_ERROR=false

if [[ "$EXIT_CODE" != "0" && "$EXIT_CODE" != "null" ]]; then
  IS_ERROR=true
fi

if [[ "$STDERR_CONTENT" == *"Error"* ]]; then
  IS_ERROR=true
fi

if [[ "$IS_ERROR" != "true" ]]; then
  exit 0
fi

# ── play sound ────────────────────────────────────────────────────────────────

CUSTOM_SOUND="${CLAUDE_SOUND_ERROR:-}"
OS="$(uname -s)"

play_sound() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[sound-error] WARNING: sound file not found: ${file}" >&2
    return 1
  fi

  case "$OS" in
    Darwin)
      afplay "$file" &>/dev/null &
      ;;
    Linux)
      if command -v paplay &>/dev/null; then
        paplay "$file" &>/dev/null &
      elif command -v aplay &>/dev/null; then
        aplay -q "$file" &>/dev/null &
      else
        echo "[sound-error] WARNING: no audio player found (tried paplay, aplay)" >&2
        return 1
      fi
      ;;
    *)
      echo "[sound-error] WARNING: unsupported OS '${OS}'" >&2
      return 1
      ;;
  esac
}

if [[ -n "$CUSTOM_SOUND" ]]; then
  play_sound "$CUSTOM_SOUND" || true
  exit 0
fi

case "$OS" in
  Darwin)
    SOUND_FILE="/System/Library/Sounds/Basso.aiff"
    if ! command -v afplay &>/dev/null; then
      echo "[sound-error] WARNING: afplay not found" >&2
      exit 0
    fi
    play_sound "$SOUND_FILE" || true
    ;;

  Linux)
    CANDIDATES=(
      "/usr/share/sounds/freedesktop/stereo/dialog-error.oga"
      "/usr/share/sounds/ubuntu/stereo/dialog-error.ogg"
      "/usr/share/sounds/gnome/default/alerts/sonar.ogg"
      "/usr/share/sounds/freedesktop/stereo/bell.oga"
    )

    SOUND_FILE=""
    for candidate in "${CANDIDATES[@]}"; do
      if [[ -f "$candidate" ]]; then
        SOUND_FILE="$candidate"
        break
      fi
    done

    if [[ -z "$SOUND_FILE" ]]; then
      echo "[sound-error] WARNING: no system error sound found on Linux" >&2
      exit 0
    fi

    play_sound "$SOUND_FILE" || true
    ;;

  *)
    echo "[sound-error] WARNING: unsupported OS '${OS}'" >&2
    ;;
esac

exit 0
