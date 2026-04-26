#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   ascii-confetti
# Event:       Stop
# Description: Prints a small colorful ASCII celebration to the terminal when
#              Claude finishes a session. Opt-in (disabled by default).
#
#              Art varies by time of day:
#                Morning   (05:00-11:59): sunrise theme
#                Afternoon (12:00-17:59): sunny theme
#                Evening   (18:00-04:59): stars theme
#
#              Color support: checks TERM and COLORTERM before emitting ANSI
#              codes. Falls back to plain ASCII if the terminal can't handle it.
#
# Config (env vars):
#   CLAUDE_CONFETTI   Set to 1 to enable.  Default: 0 (opt-in)
#
# Install — add to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "hooks": [{ "type": "command", "command": "/path/to/hooks/fun/ascii-confetti.sh" }]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── opt-in ────────────────────────────────────────────────────────────────────

[[ "${CLAUDE_CONFETTI:-0}" == "1" ]] || exit 0

# ── tty check ────────────────────────────────────────────────────────────────

[[ -t 1 ]] || exit 0

# ── color support detection ───────────────────────────────────────────────────

USE_COLOR=0
case "${TERM:-}" in
  xterm*|screen*|tmux*|rxvt*|linux|vte*)
    USE_COLOR=1 ;;
esac
[[ "${COLORTERM:-}" =~ ^(truecolor|24bit)$ ]] && USE_COLOR=1
[[ "${NO_COLOR:-}" != "" ]] && USE_COLOR=0

# ── ANSI helpers ──────────────────────────────────────────────────────────────

if [[ "$USE_COLOR" == "1" ]]; then
  R='\033[0;31m'   # red
  Y='\033[0;33m'   # yellow
  G='\033[0;32m'   # green
  B='\033[0;34m'   # blue
  M='\033[0;35m'   # magenta
  C='\033[0;36m'   # cyan
  W='\033[1;37m'   # bright white
  D='\033[0m'      # reset
else
  R=''; Y=''; G=''; B=''; M=''; C=''; W=''; D=''
fi

# ── time-of-day theme ─────────────────────────────────────────────────────────

HOUR=$(date +%H)
HOUR=${HOUR#0}  # strip leading zero for arithmetic

if [[ "$HOUR" -ge 5 && "$HOUR" -lt 12 ]]; then
  THEME="morning"
elif [[ "$HOUR" -ge 12 && "$HOUR" -lt 18 ]]; then
  THEME="afternoon"
else
  THEME="evening"
fi

# ── render ────────────────────────────────────────────────────────────────────

printf '\n'

case "$THEME" in
  morning)
    printf "${Y}        \\  |  /        ${D}\n"
    printf "${Y}      '-.;;;.-'        ${D}\n"
    printf "${Y}    -==;${W}(oOo)${Y};==-      ${D}\n"
    printf "${Y}      .-'${W}|||${Y}'-.        ${D}\n"
    printf "${Y}        /  |  \\        ${D}\n"
    printf "${W}   Good morning. Session done.${D}\n"
    ;;
  afternoon)
    printf "${Y}    ${R}*${Y}  .  ${G}*${Y}  .  ${B}*${Y}  .  ${M}*${D}\n"
    printf "${C}  .  ${Y}*${C}  .  ${R}*${C}  .  ${G}*${C}  .${D}\n"
    printf "${Y}    ${B}*${Y}  .  ${M}*${Y}  .  ${C}*${Y}  .  ${R}*${D}\n"
    printf "${W}      Session complete!${D}\n"
    ;;
  evening)
    printf "${B}  .  *  .     .  *  .  ${D}\n"
    printf "${M}     .   ${Y}*${M}  .   .   ${Y}*${M}  ${D}\n"
    printf "${B}  *  .     *  .  ${C}*${B}  .  ${D}\n"
    printf "${W}    ${C}~ Session done. Rest well. ~${D}\n"
    ;;
esac

printf '\n'

exit 0
