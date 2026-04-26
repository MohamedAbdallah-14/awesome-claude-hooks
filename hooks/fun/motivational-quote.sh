#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   motivational-quote
# Event:       Stop
# Description: Prints a random programmer quote in a simple ASCII box when
#              Claude finishes a session. Skips silently if stdout is not a tty
#              (CI, pipes, etc.).
#
#              Quotes sourced from Knuth, Dijkstra, Torvalds, Carmack, Hoare,
#              Kernighan, Pike, Spolsky, and others.
#
# Config (env vars):
#   CLAUDE_MOTIVATIONAL   Set to 0 to disable.  Default: 1
#
# Install — add to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "hooks": [{ "type": "command", "command": "/path/to/hooks/fun/motivational-quote.sh" }]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── opt-out ───────────────────────────────────────────────────────────────────

[[ "${CLAUDE_MOTIVATIONAL:-1}" == "0" ]] && exit 0

# ── tty check: skip in CI / pipes ────────────────────────────────────────────

[[ -t 1 ]] || exit 0

# ── quote bank ────────────────────────────────────────────────────────────────

QUOTES=(
  "Premature optimization is the root of all evil.|Donald Knuth"
  "Testing shows the presence of bugs, not their absence.|Edsger Dijkstra"
  "Talk is cheap. Show me the code.|Linus Torvalds"
  "The best code is no code at all.|Jeff Atwood"
  "Make it work, make it right, make it fast.|Kent Beck"
  "Simplicity is prerequisite for reliability.|Edsger Dijkstra"
  "There are only two hard things: cache invalidation and naming things.|Phil Karlton"
  "Programs must be written for people to read, and only incidentally for machines to execute.|Harold Abelson"
  "Always code as if the guy who ends up maintaining your code will be a violent psychopath who knows where you live.|John Woods"
  "Debugging is twice as hard as writing the code. If you write the code as cleverly as possible, you are, by definition, not smart enough to debug it.|Brian Kernighan"
  "The most dangerous phrase in the language is: we've always done it this way.|Grace Hopper"
  "One of my most productive days was throwing away 1000 lines of code.|Ken Thompson"
  "The function of good software is to make the complex appear simple.|Grady Booch"
  "First, solve the problem. Then, write the code.|John Johnson"
  "Any fool can write code that a computer can understand. Good programmers write code that humans can understand.|Martin Fowler"
  "The art of programming is the art of organizing complexity.|Edsger Dijkstra"
  "Measuring programming progress by lines of code is like measuring aircraft building progress by weight.|Bill Gates"
  "Before software can be reusable it first has to be usable.|Ralph Johnson"
  "The most important property of a program is whether it accomplishes the intention of its user.|C.A.R. Hoare"
  "Software is a great combination of artistry and engineering.|Bill Gates"
  "Correctness is clearly the prime quality. If the system does not do what it is supposed to do, then everything else about it matters little.|Bertrand Meyer"
  "Good software, like wine, takes time.|Joel Spolsky"
  "The key to performance is elegance, not battalions of special cases.|Jon Bentley & Doug McIlroy"
  "Give someone a program, you frustrate them for a day; teach them how to program, you frustrate them for a lifetime.|David Leinweber"
  "You can't have great software without a great team, and most software teams behave like dysfunctional families.|Jim McCarthy"
)

# ── pick a random quote ───────────────────────────────────────────────────────

TOTAL=${#QUOTES[@]}
if command -v shuf &>/dev/null; then
  IDX=$(shuf -i 0-$(( TOTAL - 1 )) -n 1 2>/dev/null || echo $(( RANDOM % TOTAL )))
else
  IDX=$(( RANDOM % TOTAL ))
fi

ENTRY="${QUOTES[$IDX]}"
QUOTE="${ENTRY%%|*}"
AUTHOR="${ENTRY##*|}"

# ── render box ────────────────────────────────────────────────────────────────

# Word-wrap at ~60 chars (pure bash, no fold needed)
wrap_text() {
  local text="$1"
  local width=60
  local line=""
  local output=""
  for word in $text; do
    if [[ $(( ${#line} + ${#word} + 1 )) -le $width ]]; then
      [[ -n "$line" ]] && line="$line $word" || line="$word"
    else
      output+="$line\n"
      line="$word"
    fi
  done
  [[ -n "$line" ]] && output+="$line"
  printf '%s' "$output"
}

WRAPPED=$(wrap_text "$QUOTE")
BOX_WIDTH=64

# Top border
printf '\n'
printf '  ╔'
printf '═%.0s' $(seq 1 $BOX_WIDTH)
printf '╗\n'

# Quote lines
while IFS= read -r line; do
  PAD=$(( BOX_WIDTH - ${#line} - 2 ))
  printf '  ║  %s%*s  ║\n' "$line" "$PAD" ""
done <<< "$(printf '%b' "$WRAPPED")"

# Divider
printf '  ╟'
printf '─%.0s' $(seq 1 $BOX_WIDTH)
printf '╢\n'

# Author line
AUTHOR_LINE="— ${AUTHOR}"
PAD=$(( BOX_WIDTH - ${#AUTHOR_LINE} - 2 ))
printf '  ║  %s%*s  ║\n' "$AUTHOR_LINE" "$PAD" ""

# Bottom border
printf '  ╚'
printf '═%.0s' $(seq 1 $BOX_WIDTH)
printf '╝\n\n'

exit 0
