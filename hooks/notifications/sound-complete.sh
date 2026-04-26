#!/usr/bin/env bash
# Hook name:   sound-complete
# Event:       Stop
# Description: Plays an audio completion chime when Claude Code finishes a task.
#              macOS: uses afplay with Glass.aiff.
#              Linux: tries paplay (PulseAudio) then aplay (ALSA) with a system sound.
#
# Config (env vars):
#   CLAUDE_SOUND_COMPLETE   Override the sound file path. Must be a valid audio
#                           file that afplay/paplay/aplay can handle.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "matcher": "",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/notifications/sound-complete.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# Consume stdin (required by the hook protocol even if unused)
INPUT=$(cat)
: "$INPUT"  # suppress unused-variable warning

CUSTOM_SOUND="${CLAUDE_SOUND_COMPLETE:-}"

OS="$(uname -s)"

play_sound() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[sound-complete] WARNING: sound file not found: ${file}" >&2
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
        echo "[sound-complete] WARNING: no audio player found (tried paplay, aplay)" >&2
        return 1
      fi
      ;;
    *)
      echo "[sound-complete] WARNING: unsupported OS '${OS}'" >&2
      return 1
      ;;
  esac
}

# ── custom override ───────────────────────────────────────────────────────────

if [[ -n "$CUSTOM_SOUND" ]]; then
  play_sound "$CUSTOM_SOUND" || true
  exit 0
fi

# ── platform defaults ─────────────────────────────────────────────────────────

case "$OS" in
  Darwin)
    SOUND_FILE="/System/Library/Sounds/Glass.aiff"
    if ! command -v afplay &>/dev/null; then
      echo "[sound-complete] WARNING: afplay not found" >&2
      exit 0
    fi
    play_sound "$SOUND_FILE" || true
    ;;

  Linux)
    # Try common XDG / freedesktop sound locations in order of preference
    CANDIDATES=(
      "/usr/share/sounds/freedesktop/stereo/complete.oga"
      "/usr/share/sounds/ubuntu/stereo/message.ogg"
      "/usr/share/sounds/gnome/default/alerts/glass.ogg"
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
      echo "[sound-complete] WARNING: no system sound file found on Linux" >&2
      exit 0
    fi

    play_sound "$SOUND_FILE" || true
    ;;

  *)
    echo "[sound-complete] WARNING: unsupported OS '${OS}' — no sound played" >&2
    ;;
esac

exit 0
