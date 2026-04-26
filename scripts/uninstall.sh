#!/usr/bin/env bash
# uninstall.sh — Remove awesome-claude-hooks entries from Claude Code settings
#
# Usage:
#   bash scripts/uninstall.sh             # removes from both global + project settings
#   bash scripts/uninstall.sh --global    # global settings only
#   bash scripts/uninstall.sh --project   # project settings only
#   bash scripts/uninstall.sh --dry-run   # show what would be removed, no changes

set -euo pipefail

# ── constants ─────────────────────────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLOBAL_SETTINGS="${HOME}/.claude/settings.json"
PROJECT_SETTINGS=".claude/settings.json"

# ── argument parsing ──────────────────────────────────────────────────────────

OPT_DRY_RUN=0
OPT_GLOBAL=0
OPT_PROJECT=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)  OPT_DRY_RUN=1 ;;
    --global)   OPT_GLOBAL=1 ;;
    --project)  OPT_PROJECT=1 ;;
    -h|--help)
      grep '^#' "$0" | head -8 | sed 's/^# //'
      exit 0
      ;;
    *)
      printf "Unknown option: %s\nRun with --help for usage.\n" "$arg" >&2
      exit 1
      ;;
  esac
done

# Default: process both
if (( OPT_GLOBAL == 0 && OPT_PROJECT == 0 )); then
  OPT_GLOBAL=1
  OPT_PROJECT=1
fi

# ── helpers ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${CYAN}  →${RESET} %s\n" "$*"; }
ok()    { printf "${GREEN}  ✓${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}  ⚠${RESET} %s\n" "$*" >&2; }
err()   { printf "${RED}  ✗${RESET} %s\n" "$*" >&2; }
header(){ printf "\n${BOLD}%s${RESET}\n" "$*"; }
dry()   { printf "${YELLOW}  [dry-run]${RESET} %s\n" "$*"; }

# ── prerequisite check ────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  err "jq not found. Install: brew install jq  or  apt-get install jq"
  exit 1
fi

# ── count matching entries ─────────────────────────────────────────────────────

count_matches() {
  local settings_file="$1"
  local repo_prefix="$2"
  [[ -f "$settings_file" ]] || { printf '0'; return; }
  jq --arg prefix "$repo_prefix" '
    [
      (.hooks // {}) |
      to_entries[] |
      .value[] |
      .hooks[]? |
      select(.command != null and (.command | startswith($prefix)))
    ] | length
  ' "$settings_file" 2>/dev/null || printf '0'
}

# ── list matching entries ──────────────────────────────────────────────────────

list_matches() {
  local settings_file="$1"
  local repo_prefix="$2"
  [[ -f "$settings_file" ]] || return 0
  jq -r --arg prefix "$repo_prefix" '
    (.hooks // {}) |
    to_entries[] |
    .key as $event |
    .value[] |
    . as $group |
    (.hooks // [])[] |
    select(.command != null and (.command | startswith($prefix))) |
    "  \($event) | \(.command)"
  ' "$settings_file" 2>/dev/null || true
}

# ── remove matching entries ────────────────────────────────────────────────────

remove_from_settings() {
  local settings_file="$1"
  local repo_prefix="$2"

  if [[ ! -f "$settings_file" ]]; then
    info "Not found, skipping: ${settings_file}"
    return
  fi

  local count
  count=$(count_matches "$settings_file" "$repo_prefix")

  if [[ "$count" -eq 0 ]]; then
    info "No entries from this repo in: ${settings_file}"
    return
  fi

  header "Found ${count} hook(s) in: ${settings_file}"
  list_matches "$settings_file" "$repo_prefix"
  echo ""

  if [[ "$OPT_DRY_RUN" == "1" ]]; then
    dry "Would remove ${count} entries from ${settings_file}"
    dry "Would back up to ${settings_file}.backup"
    return
  fi

  # Confirm unless non-interactive
  if [[ -t 0 ]]; then
    local input
    read -r -p "  Remove these ${count} entries? [y/N]: " input
    case "$input" in
      y|Y|yes|YES) ;;
      *)
        info "Skipped: ${settings_file}"
        return
        ;;
    esac
  fi

  # Backup
  cp "$settings_file" "${settings_file}.backup"
  ok "Backed up to ${settings_file}.backup"

  # Remove matching entries with jq
  # Strategy: filter out any hook command that starts with REPO_DIR
  # Also prune empty matcher groups and empty event arrays
  local updated
  updated=$(jq --arg prefix "$repo_prefix" '
    .hooks //= {} |
    .hooks |= (
      to_entries |
      map(
        .value |= (
          map(
            .hooks //= [] |
            .hooks |= map(
              select(.command == null or (.command | startswith($prefix) | not))
            ) |
            select((.hooks | length) > 0)
          ) |
          select(length > 0)
        ) |
        select(.value | length > 0)
      ) |
      from_entries
    ) |
    if (.hooks | length) == 0 then del(.hooks) else . end
  ' "$settings_file")

  printf '%s\n' "$updated" | jq . > "$settings_file"
  ok "Removed ${count} hook entries from ${settings_file}"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  printf "\n${BOLD}awesome-claude-hooks uninstaller${RESET}\n"
  printf "Repo: %s\n" "$REPO_DIR"

  local removed_any=0

  if (( OPT_GLOBAL == 1 )); then
    remove_from_settings "$GLOBAL_SETTINGS" "${REPO_DIR}/"
    removed_any=1
  fi

  if (( OPT_PROJECT == 1 )); then
    local abs_project
    abs_project="$(pwd)/${PROJECT_SETTINGS}"
    remove_from_settings "$abs_project" "${REPO_DIR}/"
    removed_any=1
  fi

  echo ""
  if [[ "$OPT_DRY_RUN" == "1" ]]; then
    warn "Dry-run mode — no files were modified."
  else
    ok "Done."
    info "Restart Claude Code for changes to take effect."
  fi
}

main "$@"
