#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# test-installer.sh — smoke-test scripts/install.sh --dry-run for every profile.
#
# For each known profile, runs the installer in dry-run mode against the global
# settings target and confirms the printed settings JSON snippet parses with
# jq. Useful as a pre-push check and as a future CI smoke test.
#
# Usage:
#   bash scripts/test-installer.sh
#
# Exit 0 if all profiles pass, 1 otherwise.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${REPO_ROOT}/scripts/install.sh"

if [[ ! -f "$INSTALLER" ]]; then
  echo "test-installer: $INSTALLER not found" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "test-installer: jq is required" >&2
  exit 1
fi

# install.sh enforces bash >= 4. On macOS the default /bin/bash is 3.2, so look
# for a 4+ binary on PATH (or in Homebrew's usual locations) before running.
find_bash4() {
  local b ver candidates
  candidates="bash /opt/homebrew/bin/bash /usr/local/bin/bash"
  for b in $candidates; do
    if command -v "$b" >/dev/null 2>&1 || [[ -x "$b" ]]; then
      ver=$("$b" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)
      if [[ "$ver" =~ ^[0-9]+$ ]] && (( ver >= 4 )); then
        printf '%s\n' "$b"
        return 0
      fi
    fi
  done
  return 1
}

if ! BASH4=$(find_bash4); then
  echo "test-installer: bash >= 4 is required to run install.sh (macOS default /bin/bash is 3.2)" >&2
  echo "test-installer: install one with 'brew install bash' and re-run" >&2
  exit 1
fi

PROFILES="safe-default security quality team devops solo-dev notifications ai-assisted"

# Strip ANSI escape sequences so "[dry-run]" markers and brace lines are
# greppable regardless of terminal color settings.
strip_ansi() {
  # Matches CSI sequences like \x1b[0;36m, \x1b[1;33m, \x1b[0m, etc.
  sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g'
}

# Pulls the JSON block that follows the "[dry-run] Settings snippet:" marker.
# install.sh pipes that block through `jq .`, so it begins with "{" on its own
# line and the matching closing "}" is also on its own line at depth 0.
extract_json() {
  awk '
    /\[dry-run\] Settings snippet:/ { in_block = 1; next }
    in_block {
      if (!started) {
        if ($0 ~ /^\{/) {
          started = 1
          depth = 0
          buf = ""
        } else {
          next
        }
      }
      buf = buf $0 "\n"
      # Strip "..." literals before counting braces so JSON string values
      # containing { or } do not skew the depth counter.
      stripped = $0
      gsub(/"[^"]*"/, "", stripped)
      n_open  = gsub(/\{/, "&", stripped)
      n_close = gsub(/\}/, "&", stripped)
      depth += n_open - n_close
      if (started && depth <= 0) {
        printf "%s", buf
        exit 0
      }
    }
  '
}

passes=0
fails=0
total=0
failed_profiles=""

for profile in $PROFILES; do
  total=$((total + 1))
  out=$("$BASH4" "$INSTALLER" --profile="$profile" --dry-run --global 2>&1 || true)
  json=$(printf '%s\n' "$out" | strip_ansi | extract_json)

  if [[ -z "$json" ]]; then
    fails=$((fails + 1))
    failed_profiles="${failed_profiles} ${profile}"
    printf '  FAIL  %-15s  no JSON block found in dry-run output\n' "$profile"
    continue
  fi

  if ! printf '%s' "$json" | jq empty >/dev/null 2>&1; then
    fails=$((fails + 1))
    failed_profiles="${failed_profiles} ${profile}"
    printf '  FAIL  %-15s  JSON block did not parse\n' "$profile"
    continue
  fi

  # Sanity: the snippet should describe a .hooks object with at least one event.
  event_count=$(printf '%s' "$json" | jq '(.hooks // {}) | length')
  if [[ -z "$event_count" || "$event_count" -lt 1 ]]; then
    fails=$((fails + 1))
    failed_profiles="${failed_profiles} ${profile}"
    printf '  FAIL  %-15s  snippet has no .hooks entries\n' "$profile"
    continue
  fi

  passes=$((passes + 1))
  printf '  OK    %-15s  %s event(s)\n' "$profile" "$event_count"
done

echo ""
if (( fails == 0 )); then
  echo "all ${total} profiles OK"
  exit 0
else
  printf 'failed: %d / %d (profiles:%s)\n' "$fails" "$total" "$failed_profiles" >&2
  exit 1
fi
