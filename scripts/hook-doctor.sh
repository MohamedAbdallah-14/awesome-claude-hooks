#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# hook-doctor.sh — read-only validator for ~/.claude/settings.json hook config.
#
# Checks:
#   - Settings JSON parses (jq empty).
#   - Each hook command's resolved path exists on disk.
#   - Hook entries live under one of the 28 supported event names.
#   - No duplicate commands within the same event (would run twice).
#   - For commands pointing inside this repo, the on-disk file matches its
#     hooks.registry.json entry (event + matcher).
#
# Usage:
#   bash scripts/hook-doctor.sh
#   bash scripts/hook-doctor.sh --settings /path/to/settings.json
#   bash scripts/hook-doctor.sh --json
#
# Exit 0 if no errors, 1 if any error-severity issues found.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REPO_ROOT}/hooks.registry.json"

VALID_EVENTS="SessionStart UserPromptSubmit UserPromptExpansion PreToolUse PermissionRequest PermissionDenied PostToolUse PostToolUseFailure PostToolBatch Notification SubagentStart SubagentStop TaskCreated TaskCompleted Stop StopFailure TeammateIdle InstructionsLoaded ConfigChange CwdChanged FileChanged WorktreeCreate WorktreeRemove PreCompact PostCompact Elicitation ElicitationResult SessionEnd"

is_valid_event() {
  local needle="$1" e
  for e in $VALID_EVENTS; do
    [[ "$e" == "$needle" ]] && return 0
  done
  return 1
}

# ── deps ──────────────────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "hook-doctor: jq is required (brew install jq)" >&2
  exit 1
fi

# ── args ──────────────────────────────────────────────────────────────────────

SETTINGS_PATH="${HOME}/.claude/settings.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --settings)
      SETTINGS_PATH="${2:-}"
      shift 2
      ;;
    --settings=*)
      SETTINGS_PATH="${1#*=}"
      shift
      ;;
    --json)
      JSON_OUT=1
      shift
      ;;
    -h|--help)
      sed -n '4,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "hook-doctor: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── findings collectors (bash 3.2 — parallel arrays, no assoc) ────────────────

# Each finding: SEVERITIES[i], EVENTS[i], COMMANDS[i], MESSAGES[i].
SEVERITIES=()
EVENTS=()
COMMANDS=()
MESSAGES=()

add_finding() {
  SEVERITIES+=("$1")
  EVENTS+=("$2")
  COMMANDS+=("$3")
  MESSAGES+=("$4")
}

# ── load + parse settings ─────────────────────────────────────────────────────

if [[ "$SETTINGS_PATH" == "/dev/stdin" ]]; then
  RAW=$(cat)
elif [[ ! -e "$SETTINGS_PATH" ]]; then
  add_finding "error" "" "" "settings file not found: $SETTINGS_PATH"
  RAW=""
else
  RAW=$(cat "$SETTINGS_PATH")
fi

if [[ -n "$RAW" ]]; then
  if ! printf '%s' "$RAW" | jq empty >/dev/null 2>&1; then
    add_finding "error" "" "" "settings JSON does not parse"
    RAW=""
  fi
fi

# ── walk hooks ────────────────────────────────────────────────────────────────

# Get list of event keys under .hooks.
EVENT_KEYS=()
if [[ -n "$RAW" ]]; then
  while IFS= read -r k; do
    [[ -n "$k" ]] && EVENT_KEYS+=("$k")
  done < <(printf '%s' "$RAW" | jq -r '.hooks // {} | keys[]?' 2>/dev/null)
fi

# Track per-event command counts for duplicate detection (parallel arrays).
DUP_KEYS=()    # "event\tcommand"
DUP_COUNTS=()  # integer

bump_dup() {
  local key="$1" i
  for ((i=0; i<${#DUP_KEYS[@]}; i++)); do
    if [[ "${DUP_KEYS[$i]}" == "$key" ]]; then
      DUP_COUNTS[$i]=$((DUP_COUNTS[i] + 1))
      return 0
    fi
  done
  DUP_KEYS+=("$key")
  DUP_COUNTS+=(1)
}

# ── load registry once (path -> "event\tmatcher") ─────────────────────────────

REG_PATHS=()
REG_INFO=()

if [[ -f "$REGISTRY" ]]; then
  if jq empty "$REGISTRY" >/dev/null 2>&1; then
    while IFS=$'\t' read -r p e m; do
      [[ -z "$p" ]] && continue
      REG_PATHS+=("$p")
      REG_INFO+=("$e"$'\t'"$m")
    done < <(jq -r '.hooks[]? | [.path, (.event // ""), (.matcher // "")] | @tsv' "$REGISTRY")
  else
    add_finding "warn" "" "" "hooks.registry.json is present but does not parse — skipping cross-checks"
  fi
fi

registry_lookup() {
  # Echoes "event\tmatcher" for the registry entry matching the given repo-relative path, or empty.
  local rel="$1" i
  for ((i=0; i<${#REG_PATHS[@]}; i++)); do
    if [[ "${REG_PATHS[$i]}" == "$rel" ]]; then
      printf '%s' "${REG_INFO[$i]}"
      return 0
    fi
  done
  return 1
}

# ── iterate ───────────────────────────────────────────────────────────────────

for ev in "${EVENT_KEYS[@]}"; do
  if ! is_valid_event "$ev"; then
    add_finding "error" "$ev" "" "unknown event name (not in the 28 supported events)"
  fi

  # For each entry under this event, expand to one command per line:
  #   <matcher>\t<command>
  while IFS=$'\t' read -r matcher cmd; do
    [[ -z "$cmd" ]] && continue

    # Duplicate within the same event?
    bump_dup "${ev}"$'\t'"${cmd}"

    # Path checks: only meaningful for absolute paths or paths that exist.
    # Strip surrounding quotes / leading tokens — hooks are typically
    # `command: "/abs/path/foo.sh"` but users sometimes wrap with `bash`.
    # Take the first whitespace-separated token that looks like a path.
    candidate=""
    # shellcheck disable=SC2086
    for tok in $cmd; do
      case "$tok" in
        /*|~/*|./*) candidate="$tok"; break ;;
      esac
    done
    if [[ -z "$candidate" && "$cmd" == /* ]]; then
      candidate="$cmd"
    fi

    if [[ -z "$candidate" ]]; then
      add_finding "info" "$ev" "$cmd" "command is not an absolute path; cannot verify file existence"
      continue
    fi

    # Expand leading tilde to $HOME.
    if [[ "${candidate:0:2}" == $'\x7e/' ]]; then
      candidate="${HOME}/${candidate:2}"
    fi

    if [[ ! -e "$candidate" ]]; then
      add_finding "error" "$ev" "$cmd" "referenced file does not exist on disk: $candidate"
      continue
    fi

    # If path is inside this repo, cross-check registry.
    if [[ "$candidate" == "${REPO_ROOT}/"* ]]; then
      rel="${candidate#"${REPO_ROOT}"/}"
      if reg=$(registry_lookup "$rel"); then
        reg_event="${reg%%$'\t'*}"
        reg_matcher="${reg#*$'\t'}"
        if [[ -n "$reg_event" && "$reg_event" != "$ev" ]]; then
          add_finding "warn" "$ev" "$cmd" "registered under event '${reg_event}' in hooks.registry.json but configured under '${ev}'"
        fi
        if [[ -n "$reg_matcher" && "$reg_matcher" != "$matcher" ]]; then
          add_finding "warn" "$ev" "$cmd" "registry matcher '${reg_matcher}' does not match settings matcher '${matcher}'"
        fi
      fi
    fi
  done < <(printf '%s' "$RAW" | jq -r --arg ev "$ev" '
    .hooks[$ev] // [] |
    map(
      . as $entry |
      ($entry.matcher // "") as $m |
      ($entry.hooks // []) |
      map([$m, (.command // "")] | @tsv)
    ) | flatten | .[]
  ' 2>/dev/null)
done

# Promote dup counts > 1 to findings.
for ((i=0; i<${#DUP_KEYS[@]}; i++)); do
  if (( DUP_COUNTS[i] > 1 )); then
    ev="${DUP_KEYS[$i]%%$'\t'*}"
    cmd="${DUP_KEYS[$i]#*$'\t'}"
    add_finding "warn" "$ev" "$cmd" "duplicate command appears ${DUP_COUNTS[$i]} times under event '${ev}' (will run multiple times)"
  fi
done

# ── output ────────────────────────────────────────────────────────────────────

n=${#SEVERITIES[@]}
errors=0
warnings=0
infos=0
for ((i=0; i<n; i++)); do
  case "${SEVERITIES[$i]}" in
    error) errors=$((errors + 1)) ;;
    warn)  warnings=$((warnings + 1)) ;;
    info)  infos=$((infos + 1)) ;;
  esac
done

if (( JSON_OUT == 1 )); then
  # Build JSON array via jq -n with --argjson length and per-finding args.
  out='[]'
  for ((i=0; i<n; i++)); do
    out=$(jq -n \
      --argjson acc "$out" \
      --arg sev "${SEVERITIES[$i]}" \
      --arg ev "${EVENTS[$i]}" \
      --arg cmd "${COMMANDS[$i]}" \
      --arg msg "${MESSAGES[$i]}" \
      '$acc + [{severity: $sev, event: $ev, command: $cmd, message: $msg}]')
  done
  jq -n \
    --arg settings "$SETTINGS_PATH" \
    --argjson findings "$out" \
    --argjson errors "$errors" \
    --argjson warnings "$warnings" \
    --argjson infos "$infos" \
    '{settings: $settings, summary: {errors: $errors, warnings: $warnings, infos: $infos}, findings: $findings}'
else
  echo "hook-doctor: settings = $SETTINGS_PATH"
  if (( n == 0 )); then
    echo "  no findings."
  else
    for ((i=0; i<n; i++)); do
      sev="${SEVERITIES[$i]}"
      ev="${EVENTS[$i]}"
      cmd="${COMMANDS[$i]}"
      msg="${MESSAGES[$i]}"
      label=""
      [[ -n "$ev" ]] && label="[$ev] "
      [[ -n "$cmd" ]] && label="${label}${cmd} — "
      printf '  %-5s %s%s\n' "$sev" "$label" "$msg"
    done
  fi
  echo ""
  echo "summary: ${errors} error(s), ${warnings} warning(s), ${infos} info"
fi

if (( errors > 0 )); then
  exit 1
fi
exit 0
