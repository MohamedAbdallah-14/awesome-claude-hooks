#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# install.sh — Interactive installer for awesome-claude-hooks
#
# Usage:
#   bash scripts/install.sh                          # interactive mode
#   bash scripts/install.sh --all                    # install all hooks
#   bash scripts/install.sh --category=security      # one category non-interactively
#   bash scripts/install.sh --profile=safe-default   # install a curated profile
#   bash scripts/install.sh --list-profiles          # show available profiles
#   bash scripts/install.sh --dry-run                # show what would happen, no changes
#   bash scripts/install.sh --all --global           # install all to global settings
#   bash scripts/install.sh --all --project          # install all to project settings
#
# Profiles (from hooks.registry.yaml):
#   safe-default   audit + summary + context guard + desktop notification
#   security       block-secrets, protect-dotenv, dangerous-bash, system-paths,
#                  sql-injection, npm-audit, audit-bash, audit-writes
#   quality        eslint, prettier, tsc, json/yaml validator, python-lint,
#                  dart-analyze, go-vet, test-coverage
#   team           protect-main, validate-commit-msg, audit, summary,
#                  conflict-detector, stash-guard
#   devops         terraform, kubernetes, aws, db-migration, docker, gh-actions,
#                  infra-audit-log
#   solo-dev       auto-format-on-save, ai-commit-message, session-name, notify,
#                  session-start-context
#   notifications  desktop, macos, linux, slack, telegram, discord, pushover,
#                  sound-complete, sound-error, terminal-title
#   ai-assisted    ai-code-review, ai-security-scan, ai-commit-message,
#                  ai-pr-description, ai-migration-safety

set -euo pipefail

# ── constants ─────────────────────────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${REPO_DIR}/hooks"

GLOBAL_SETTINGS="${HOME}/.claude/settings.json"
PROJECT_SETTINGS=".claude/settings.json"

# All categories with hooks present in the repo (auto-discovered).
ALL_CATEGORIES=()
while IFS= read -r dir; do
  ALL_CATEGORIES+=("$(basename "$dir")")
done < <(find "${HOOKS_DIR}" -mindepth 1 -maxdepth 1 -type d -not -name '_*' | sort)

if [[ ${#ALL_CATEGORIES[@]} -eq 0 ]]; then
  echo "No hook categories found under ${HOOKS_DIR}" >&2
  exit 1
fi

# ── argument parsing ──────────────────────────────────────────────────────────

OPT_ALL=0
OPT_DRY_RUN=0
OPT_CATEGORY=""
OPT_PROFILE=""
OPT_LIST_PROFILES=0
OPT_TARGET=""   # "global" | "project" | "" (ask interactively)

REGISTRY_JSON="${REPO_DIR}/hooks.registry.json"

for arg in "$@"; do
  case "$arg" in
    --all)             OPT_ALL=1 ;;
    --dry-run)         OPT_DRY_RUN=1 ;;
    --global)          OPT_TARGET="global" ;;
    --project)         OPT_TARGET="project" ;;
    --category=*)      OPT_CATEGORY="${arg#--category=}" ;;
    --profile=*)       OPT_PROFILE="${arg#--profile=}" ;;
    --list-profiles)   OPT_LIST_PROFILES=1 ;;
    -h|--help)
      grep '^#' "$0" | head -36 | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ── profile discovery ─────────────────────────────────────────────────────────

if [[ "$OPT_LIST_PROFILES" == "1" ]]; then
  if [[ ! -f "$REGISTRY_JSON" ]]; then
    echo "$REGISTRY_JSON not found — run 'python3 scripts/build-registry.py'" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq required for --list-profiles" >&2
    exit 1
  fi
  jq -r '.profiles | to_entries[] | "\(.key) (\(.value | length) hooks)\n  \(.value | join(", "))\n"' \
    "$REGISTRY_JSON"
  exit 0
fi

# Resolve profile to a list of hook paths.
resolve_profile() {
  local profile="$1"
  if [[ ! -f "$REGISTRY_JSON" ]]; then
    echo "$REGISTRY_JSON not found — run 'python3 scripts/build-registry.py'" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq required to resolve --profile" >&2
    exit 1
  fi
  local ids
  ids=$(jq -er --arg p "$profile" '
    (.profiles[$p] // empty)
    | if . == null then halt_error(2) else .[] end
  ' "$REGISTRY_JSON" 2>/dev/null) || {
    echo "Unknown profile: $profile" >&2
    echo "Run with --list-profiles to see available profiles." >&2
    exit 1
  }
  # Each id resolves to its registry path.
  local id path
  while IFS= read -r id; do
    path=$(jq -r --arg id "$id" '.hooks[] | select(.id==$id) | .path' "$REGISTRY_JSON")
    if [[ -z "$path" ]]; then
      echo "Profile references unknown hook id: $id" >&2
      exit 1
    fi
    printf '%s/%s\n' "$REPO_DIR" "$path"
  done <<< "$ids"
}

# ── helpers ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { printf "${CYAN}  →${RESET} %s\n" "$*"; }
ok()      { printf "${GREEN}  ✓${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠${RESET} %s\n" "$*" >&2; }
err()     { printf "${RED}  ✗${RESET} %s\n" "$*" >&2; }
header()  { printf "\n${BOLD}%s${RESET}\n" "$*"; }
dry()     { printf "${YELLOW}  [dry-run]${RESET} %s\n" "$*"; }

# ── prerequisite checks ───────────────────────────────────────────────────────

check_prerequisites() {
  header "Checking prerequisites"

  local ok=1

  # bash >= 4
  local bash_major
  bash_major="${BASH_VERSINFO[0]}"
  if (( bash_major < 4 )); then
    err "bash >= 4 required (found $BASH_VERSION). On macOS: brew install bash"
    ok=0
  else
    ok "bash ${BASH_VERSION}"
  fi

  # jq
  if ! command -v jq &>/dev/null; then
    err "jq not found. Install: brew install jq  or  apt-get install jq"
    ok=0
  else
    ok "jq $(jq --version 2>/dev/null || echo '(found)')"
  fi

  # Claude Code CLI
  if ! command -v claude &>/dev/null; then
    warn "claude CLI not found on PATH. Hooks will still be installed, but you won't be able to run Claude Code from this shell."
  else
    ok "claude $(claude --version 2>/dev/null | head -1 || echo '(found)')"
  fi

  if (( ok == 0 )); then
    echo ""
    err "Prerequisites not met. Fix the errors above and re-run."
    exit 1
  fi
}

# ── discover hooks in a category ─────────────────────────────────────────────

# Outputs lines of: <hook_file_path>|<hook_name>|<event>|<description>
list_hooks_in_category() {
  local category="$1"
  local dir="${HOOKS_DIR}/${category}"
  [[ -d "$dir" ]] || return 0

  local f name event desc
  for f in "${dir}"/*.sh; do
    [[ -f "$f" ]] || continue
    name=$(grep -m1 '^# Hook name:' "$f" 2>/dev/null | sed 's/^# Hook name:[[:space:]]*//' | xargs || basename "$f" .sh)
    event=$(grep -m1 '^# Event:' "$f" 2>/dev/null | sed 's/^# Event:[[:space:]]*//' | xargs || echo "unknown")
    desc=$(grep -m1 '^# Description:' "$f" 2>/dev/null | sed 's/^# Description:[[:space:]]*//' | xargs || echo "")
    printf '%s|%s|%s|%s\n' "$f" "$name" "$event" "$desc"
  done
}

# ── interactive category selection ────────────────────────────────────────────

select_categories_plain() {
  header "Select categories to install"
  echo "  Available categories:"
  local i=1
  for cat in "${ALL_CATEGORIES[@]}"; do
    local count
    count=$(find "${HOOKS_DIR}/${cat}" -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
    printf "  %2d) %-20s  (%s hooks)\n" "$i" "$cat" "$count"
    (( i++ ))
  done
  echo "   a) All categories"
  echo ""

  local input selected_cats=()
  while true; do
    read -r -p "  Enter numbers separated by spaces, or 'a' for all: " input
    if [[ "$input" == "a" || "$input" == "A" ]]; then
      selected_cats=("${ALL_CATEGORIES[@]}")
      break
    fi
    local valid=1
    selected_cats=()
    for token in $input; do
      if [[ "$token" =~ ^[0-9]+$ ]] && (( token >= 1 && token <= ${#ALL_CATEGORIES[@]} )); then
        selected_cats+=("${ALL_CATEGORIES[$((token-1))]}")
      else
        warn "Invalid selection: $token"
        valid=0
        break
      fi
    done
    (( valid == 1 )) && [[ ${#selected_cats[@]} -gt 0 ]] && break
    warn "Please enter valid numbers."
  done

  # Return via global
  SELECTED_CATEGORIES=("${selected_cats[@]}")
}

# ── interactive hook selection within a category ──────────────────────────────

# Sets SELECTED_HOOKS (array of absolute paths)
select_hooks_in_category() {
  local category="$1"
  local -a hook_paths hook_names hook_events hook_descs

  while IFS='|' read -r fpath fname fevent fdesc; do
    hook_paths+=("$fpath")
    hook_names+=("$fname")
    hook_events+=("$fevent")
    hook_descs+=("$fdesc")
  done < <(list_hooks_in_category "$category")

  if [[ ${#hook_paths[@]} -eq 0 ]]; then
    warn "No hooks found in category: $category"
    return
  fi

  header "Category: ${category} (${#hook_paths[@]} hooks)"
  local i
  for (( i=0; i<${#hook_paths[@]}; i++ )); do
    printf "  %2d) %-35s  [%s]\n" "$((i+1))" "${hook_names[$i]}" "${hook_events[$i]}"
    [[ -n "${hook_descs[$i]}" ]] && printf "       %s\n" "${hook_descs[$i]}"
  done
  echo "   a) All hooks in this category"
  echo "   s) Skip this category"
  echo ""

  local input
  while true; do
    read -r -p "  Select hooks (numbers, 'a' for all, 's' to skip): " input
    if [[ "$input" == "s" || "$input" == "S" ]]; then
      return
    fi
    if [[ "$input" == "a" || "$input" == "A" ]]; then
      SELECTED_HOOKS+=("${hook_paths[@]}")
      return
    fi
    local valid=1
    local batch=()
    for token in $input; do
      if [[ "$token" =~ ^[0-9]+$ ]] && (( token >= 1 && token <= ${#hook_paths[@]} )); then
        batch+=("${hook_paths[$((token-1))]}")
      else
        warn "Invalid selection: $token"
        valid=0
        break
      fi
    done
    if (( valid == 1 )) && [[ ${#batch[@]} -gt 0 ]]; then
      SELECTED_HOOKS+=("${batch[@]}")
      return
    fi
    warn "Please enter valid numbers."
  done
}

# ── build settings.json snippet ───────────────────────────────────────────────

# Full set of Claude Code hook events. Keep in sync with
# scripts/lint-hooks.sh:VALID_EVENTS and docs/hook-contract.md.
# Source: https://code.claude.com/docs/en/hooks
HOOK_EVENT_NAMES='SessionStart|UserPromptSubmit|UserPromptExpansion|PreToolUse|PermissionRequest|PermissionDenied|PostToolUse|PostToolUseFailure|PostToolBatch|Notification|SubagentStart|SubagentStop|TaskCreated|TaskCompleted|Stop|StopFailure|TeammateIdle|InstructionsLoaded|ConfigChange|CwdChanged|FileChanged|WorktreeCreate|WorktreeRemove|PreCompact|PostCompact|Elicitation|ElicitationResult|SessionEnd'

# Reads hook metadata from file header, emits one TSV row:
#   <event>\t<matcher>\t<absolute_path>
# Fails loudly when the header is missing or names an unknown event.
# Silent fallback to Stop is gone — bad metadata should not install hooks
# under the wrong event.
get_hook_meta() {
  local fpath="$1"
  local event_line
  event_line=$(grep -m1 '^# Event:' "$fpath" 2>/dev/null | sed 's/^# Event:[[:space:]]*//' | xargs || true)

  if [[ -z "$event_line" ]]; then
    err "Missing '# Event:' header in $fpath"
    exit 1
  fi

  local event matcher=""
  if [[ "$event_line" =~ ^($HOOK_EVENT_NAMES)([[:space:]]+\(matcher:[[:space:]]*\"([^\"]+)\"\))?[[:space:]]*$ ]]; then
    event="${BASH_REMATCH[1]}"
    matcher="${BASH_REMATCH[3]:-}"
  else
    err "Unknown hook event in $fpath: '$event_line'"
    err "Valid events: $(printf '%s' "$HOOK_EVENT_NAMES" | tr '|' ' ')"
    exit 1
  fi

  printf '%s\t%s\t%s\n' "$event" "$matcher" "$fpath"
}

# Builds the full hooks object to merge, output as JSON string
build_hooks_json() {
  local -a hook_files=("$@")

  # Group hooks by event+matcher into a temp associative array
  # We'll build JSON manually using jq
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local meta_file="${tmp_dir}/meta.tsv"

  local f
  for f in "${hook_files[@]}"; do
    get_hook_meta "$f" >> "$meta_file"
  done

  # Use jq to assemble the settings snippet
  # Input: TSV with columns: event, matcher, command_path
  # Output: { "hooks": { "Stop": [...], "PreToolUse": [...], ... } }

  local json
  json=$(jq -Rsn '
    [ inputs | split("\n") | .[] | select(length > 0) | split("\t") |
      { event: .[0], matcher: .[1], command: .[2] }
    ] |
    group_by(.event) |
    map({
      key: .[0].event,
      value: (
        group_by(.matcher) |
        map({
          matcher: (.[0].matcher // ""),
          hooks: map({ type: "command", command: .command })
        })
      )
    }) |
    from_entries |
    { hooks: . }
  ' "$meta_file")

  rm -rf "$tmp_dir"
  printf '%s' "$json"
}

# ── settings.json merge ────────────────────────────────────────────────────────

# Deep-merges new_hooks into existing_settings at the .hooks key level.
# Appends entries to each event's hook list rather than replacing.
merge_settings() {
  local existing_file="$1"
  local new_hooks_json="$2"

  local existing="{}"
  if [[ -f "$existing_file" ]]; then
    existing=$(cat "$existing_file")
  fi

  # Merge strategy: for each event, drop any new commands that are already
  # registered for that event, then append the remaining ones. Dedupe is
  # per-command, not per-group — otherwise a partially-overlapping group
  # (one new command alongside one already-registered command) would be
  # appended whole and produce duplicate entries.
  jq -n \
    --argjson existing "$existing" \
    --argjson new_hooks "$new_hooks_json" '
    $existing as $base |
    ($new_hooks.hooks // {}) |
    to_entries |
    reduce .[] as $event_entry (
      $base;
      ([ (.hooks[$event_entry.key] // [])[]
         | (.hooks // [])[] | .command ]) as $existing_cmds
      | .hooks[$event_entry.key] //= []
      | .hooks[$event_entry.key] += (
          $event_entry.value
          | map(
              .hooks |= map(select(.command as $c | $existing_cmds | index($c) | not))
            )
          | map(select((.hooks // []) | length > 0))
        )
    )
  '
}

# ── target path selection ─────────────────────────────────────────────────────

select_target() {
  if [[ "$OPT_TARGET" == "global" ]]; then
    TARGET_SETTINGS="$GLOBAL_SETTINGS"
    return
  fi
  if [[ "$OPT_TARGET" == "project" ]]; then
    TARGET_SETTINGS="$PROJECT_SETTINGS"
    return
  fi

  header "Installation target"
  echo "  1) Global  — ${GLOBAL_SETTINGS}"
  echo "  2) Project — ${PROJECT_SETTINGS}  (relative to current directory)"
  echo ""

  local input
  while true; do
    read -r -p "  Install to [1/2]: " input
    case "$input" in
      1) TARGET_SETTINGS="$GLOBAL_SETTINGS"; return ;;
      2) TARGET_SETTINGS="$PROJECT_SETTINGS"; return ;;
      *) warn "Enter 1 or 2." ;;
    esac
  done
}

# ── validation ────────────────────────────────────────────────────────────────

validate_hook() {
  local hook="$1"
  local test_event="Stop"

  # Pick a realistic test payload based on event type
  local payload
  payload=$(jq -n \
    --arg session "test-$(date +%s)" \
    '{
      hook_event_name: "Stop",
      session_id: $session,
      transcript_path: "/tmp/test-transcript",
      stop_hook_active: true
    }')

  local event_line
  event_line=$(grep -m1 '^# Event:' "$hook" 2>/dev/null | sed 's/^# Event:[[:space:]]*//' | xargs || echo "Stop")

  if [[ "$event_line" =~ PreToolUse ]]; then
    payload=$(jq -n \
      --arg session "test-$(date +%s)" \
      '{
        hook_event_name: "PreToolUse",
        session_id: $session,
        transcript_path: "/tmp/test-transcript",
        tool_name: "Read",
        tool_input: { file_path: "/tmp/test-file" }
      }')
    test_event="PreToolUse"
  fi

  local exit_code=0
  local output
  output=$(printf '%s' "$payload" | timeout 5 bash "$hook" 2>&1) || exit_code=$?

  # Exit 0 = allow, exit 2 = block (both valid), anything else is unexpected
  if (( exit_code == 0 || exit_code == 2 )); then
    ok "Validation passed: $(basename "$hook")  (exit ${exit_code})"
  else
    warn "Validation returned exit ${exit_code} for $(basename "$hook"). Output: ${output:-<none>}"
  fi
}

# ── write settings ────────────────────────────────────────────────────────────

write_settings() {
  local target="$1"
  local new_hooks_json="$2"
  local -a hook_files=("${@:3}")

  local target_dir
  target_dir="$(dirname "$target")"

  if [[ "$OPT_DRY_RUN" == "1" ]]; then
    dry "Would write to: ${target}"
    dry "Settings snippet:"
    printf '%s\n' "$new_hooks_json" | jq .
    return
  fi

  # Backup existing settings
  if [[ -f "$target" ]]; then
    cp "$target" "${target}.backup"
    info "Backed up existing settings to ${target}.backup"
  fi

  # Create directory if needed
  mkdir -p "$target_dir"

  # Merge and write
  local merged
  merged=$(merge_settings "$target" "$new_hooks_json")
  printf '%s\n' "$merged" | jq . > "$target"
  ok "Settings written to ${target}"
}

# ── chmod hooks ───────────────────────────────────────────────────────────────

make_executable() {
  local -a files=("$@")
  local f
  for f in "${files[@]}"; do
    if [[ "$OPT_DRY_RUN" == "1" ]]; then
      dry "Would chmod +x ${f}"
    else
      chmod +x "$f"
    fi
  done
}

# ── report ────────────────────────────────────────────────────────────────────

print_report() {
  local target="$1"
  local -a hooks=("${@:2}")

  header "Installation summary"
  printf "  Target: %s\n" "$target"
  printf "  Hooks installed: %d\n\n" "${#hooks[@]}"

  local f
  for f in "${hooks[@]}"; do
    local rel="${f#"${REPO_DIR}/"}"
    printf "  • %s\n" "$rel"
  done

  echo ""
  info "Restart Claude Code for hooks to take effect."
  if [[ "$OPT_DRY_RUN" == "1" ]]; then
    echo ""
    warn "Dry-run mode — no files were modified."
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  printf "\n${BOLD}awesome-claude-hooks installer${RESET}\n"
  printf "Repo: %s\n" "$REPO_DIR"

  check_prerequisites

  # Determine which hooks to install
  SELECTED_HOOKS=()
  SELECTED_CATEGORIES=()

  if [[ -n "$OPT_PROFILE" ]]; then
    # Non-interactive: profile resolved via the registry.
    while IFS= read -r fpath; do
      [[ -n "$fpath" ]] || continue
      if [[ ! -f "$fpath" ]]; then
        err "Profile points at a missing hook: $fpath"
        exit 1
      fi
      SELECTED_HOOKS+=("$fpath")
      cat=$(basename "$(dirname "$fpath")")
      if [[ ! " ${SELECTED_CATEGORIES[*]:-} " == *" $cat "* ]]; then
        SELECTED_CATEGORIES+=("$cat")
      fi
    done < <(resolve_profile "$OPT_PROFILE")

  elif [[ -n "$OPT_CATEGORY" ]]; then
    # Non-interactive: single category
    if [[ ! -d "${HOOKS_DIR}/${OPT_CATEGORY}" ]]; then
      err "Category '${OPT_CATEGORY}' not found. Available: ${ALL_CATEGORIES[*]}"
      exit 1
    fi
    SELECTED_CATEGORIES=("$OPT_CATEGORY")
    while IFS='|' read -r fpath _rest; do
      SELECTED_HOOKS+=("$fpath")
    done < <(list_hooks_in_category "$OPT_CATEGORY")

  elif [[ "$OPT_ALL" == "1" ]]; then
    # Non-interactive: all hooks
    SELECTED_CATEGORIES=("${ALL_CATEGORIES[@]}")
    for cat in "${ALL_CATEGORIES[@]}"; do
      while IFS='|' read -r fpath _rest; do
        SELECTED_HOOKS+=("$fpath")
      done < <(list_hooks_in_category "$cat")
    done

  else
    # Interactive
    select_categories_plain
    for cat in "${SELECTED_CATEGORIES[@]}"; do
      select_hooks_in_category "$cat"
    done
  fi

  if [[ ${#SELECTED_HOOKS[@]} -eq 0 ]]; then
    warn "No hooks selected. Nothing to install."
    exit 0
  fi

  # Select target settings.json
  select_target

  # Make hooks executable
  header "Making hooks executable"
  make_executable "${SELECTED_HOOKS[@]}"
  [[ "$OPT_DRY_RUN" == "0" ]] && ok "chmod +x applied to ${#SELECTED_HOOKS[@]} hooks"

  # Build settings snippet
  header "Building settings.json snippet"
  local new_hooks_json
  new_hooks_json=$(build_hooks_json "${SELECTED_HOOKS[@]}")

  # Write merged settings
  header "Writing settings"
  write_settings "$TARGET_SETTINGS" "$new_hooks_json" "${SELECTED_HOOKS[@]}"

  # Run validation on first hook
  if [[ "$OPT_DRY_RUN" == "0" && ${#SELECTED_HOOKS[@]} -gt 0 ]]; then
    header "Validation"
    validate_hook "${SELECTED_HOOKS[0]}"
  fi

  # Final report
  print_report "$TARGET_SETTINGS" "${SELECTED_HOOKS[@]}"
}

main "$@"
