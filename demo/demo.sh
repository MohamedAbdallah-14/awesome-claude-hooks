#!/usr/bin/env bash
# Scripted demo of awesome-claude-hooks. Drives:
#   1. installer dry-run on the security profile
#   2. a synthetic PreToolUse payload denied by protect-dotenv
#   3. a synthetic PreToolUse payload allowed for a normal file
#
# Sleeps are tuned for a terminal recording (asciinema).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PROMPT='\033[1;36m$\033[0m'
HEADER='\033[1;33m'
DIM='\033[2m'
OK='\033[0;32m'
DENY='\033[0;31m'
RESET='\033[0m'

pause() { sleep "${1:-0.6}"; }
type_out() {
  printf '%b ' "$PROMPT"
  local s="$1"
  local i
  for (( i=0; i<${#s}; i++ )); do
    printf '%s' "${s:$i:1}"
    sleep 0.018
  done
  printf '\n'
}

clear

printf "%bawesome-claude-hooks · 60-second demo%b\n" "$HEADER" "$RESET"
printf "%b—%b\n" "$DIM" "$RESET"
pause 1

# 1 — preview the security profile
type_out "bash scripts/install.sh --profile=security --dry-run --global"
pause 0.4
bash scripts/install.sh --profile=security --dry-run --global 2>&1 | sed -n '1,30p'
pause 1.5

printf "\n"

# 2 — synthetic Write to .env, denied
type_out 'echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\".env\",\"content\":\"API=sk-...\"}}" \\'
type_out '  | hooks/security/protect-dotenv.sh'
pause 0.4
printf "%b" "$DENY"
echo '{"tool_name":"Write","tool_input":{"file_path":".env","content":"API=sk-..."}}' \
  | bash hooks/security/protect-dotenv.sh \
  | jq .
printf "%b" "$RESET"
pause 1.5

printf "\n"

# 3 — synthetic Write to a normal file, allowed
type_out 'echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"src/app.ts\",...}}" \\'
type_out '  | hooks/security/protect-dotenv.sh'
pause 0.4
out=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/app.ts","content":"export {}"}}' \
  | bash hooks/security/protect-dotenv.sh)
if [ -z "$out" ]; then
  printf "%b(no output → tool call allowed)%b\n" "$OK" "$RESET"
else
  printf '%s\n' "$out"
fi
pause 1.5

printf "\n%bDone. 90 hooks · 8 profiles · spec-aligned.%b\n" "$HEADER" "$RESET"
pause 1
