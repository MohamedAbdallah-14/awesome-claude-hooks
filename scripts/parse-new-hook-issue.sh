#!/usr/bin/env bash
# parse-new-hook-issue.sh — extract structured fields from an issue body
# rendered by .github/ISSUE_TEMPLATE/new_hook.yml.
#
# GitHub renders form responses as:
#
#   ### <Field label>
#
#   <user content>
#
#   ### <Next field label>
#
# We rely on the labels being stable in the form definition. Any change to
# new_hook.yml field labels needs a matching change here.
#
# Outputs (via $GITHUB_OUTPUT):
#   valid=true|false
#   errors=<multiline list when invalid>
#   name|category|event|matcher|description|bypass|style  when valid
#
# Inputs (env):
#   BODY            issue body
#   GITHUB_OUTPUT   (provided by Actions)

set -euo pipefail

if [[ -z "${BODY:-}" ]]; then
  echo "BODY env var required" >&2
  exit 1
fi

emit_output() {
  # emit_output <key> <value>
  # Multi-line-safe: uses heredoc form per Actions spec.
  local key="$1" val="$2"
  local delim
  delim="EOF_$(date +%s%N)_$RANDOM"
  {
    printf '%s<<%s\n' "$key" "$delim"
    printf '%s\n' "$val"
    printf '%s\n' "$delim"
  } >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

# Pull the content under a "### <label>" heading until the next heading.
# Trims trailing whitespace and ignores literal "_No response_".
extract() {
  local label="$1"
  python3 - "$label" <<'PY'
import os, re, sys
body = os.environ.get("BODY", "")
label = sys.argv[1]
# Match the heading line, capture everything until the next "### " heading
# or end of body. Anchored at line start to avoid catching inline `### foo`.
pat = re.compile(
    r"^###\s+" + re.escape(label) + r"\s*\n(.*?)(?=^###\s+|\Z)",
    re.M | re.S,
)
m = pat.search(body)
if not m:
    print("", end="")
    sys.exit(0)
val = m.group(1).strip()
if val == "_No response_":
    val = ""
print(val, end="")
PY
}

NAME=$(extract "Proposed hook name")
CATEGORY=$(extract "Category")
EVENT=$(extract "Hook event")
MATCHER=$(extract "Matcher (if PreToolUse/PostToolUse)")
WHAT=$(extract "What it does")
RISK=$(extract "Risk level")
BYPASS=$(extract "Bypass env var")

# Use the first paragraph of "What it does" as the one-line description.
# Collapse to a single line and strip control chars — the value lands in a
# header comment via printf %s, so newlines/tabs would break the block.
DESCRIPTION=$(printf '%s' "$WHAT" \
  | awk 'BEGIN{p=""} /^$/ {if(p) exit} {p=p (p?" ":"") $0} END{print p}' \
  | tr -d '\r\t' \
  | tr -s ' ' \
  | cut -c1-280)

# Style follows risk level: blocking/privileged hooks default to JSON+exit 0
# (Style B). Everything else is also Style B since it's the recommended form.
STYLE="B"

# ── validation ────────────────────────────────────────────────────────────────

ERRORS=""
add_err() { ERRORS="${ERRORS}- ${1}"$'\n'; }

# Name: kebab-case, 3–40 chars, lowercase + digits + dashes only.
if [[ -z "$NAME" ]]; then
  add_err "**Name** is empty."
elif [[ ! "$NAME" =~ ^[a-z][a-z0-9-]{2,39}$ ]]; then
  add_err "**Name** must be kebab-case (lowercase, digits, dashes), 3–40 chars, starting with a letter. Got: \`$NAME\`."
fi

# Category: must match an existing dir under hooks/.
VALID_CATEGORIES="ai automation context cost devops fun git notifications prompt quality security session"
if [[ -z "$CATEGORY" ]]; then
  add_err "**Category** is empty."
else
  found=0
  for c in $VALID_CATEGORIES; do
    [[ "$c" == "$CATEGORY" ]] && found=1 && break
  done
  if [[ $found -eq 0 ]]; then
    add_err "**Category** \`$CATEGORY\` is not one of: $VALID_CATEGORIES."
  fi
fi

# Event: must match the contract's allowlist.
VALID_EVENTS="SessionStart UserPromptSubmit UserPromptExpansion PreToolUse PermissionRequest PermissionDenied PostToolUse PostToolUseFailure PostToolBatch Notification SubagentStart SubagentStop TaskCreated TaskCompleted Stop StopFailure TeammateIdle InstructionsLoaded ConfigChange CwdChanged FileChanged WorktreeCreate WorktreeRemove PreCompact PostCompact Elicitation ElicitationResult SessionEnd"
if [[ -z "$EVENT" ]]; then
  add_err "**Event** is empty."
else
  found=0
  for e in $VALID_EVENTS; do
    [[ "$e" == "$EVENT" ]] && found=1 && break
  done
  if [[ $found -eq 0 ]]; then
    add_err "**Event** \`$EVENT\` is not in the contract's allowlist."
  fi
fi

# Matcher: must be empty or alphanumeric+pipe (allowing word + `|`).
if [[ -n "$MATCHER" ]] && [[ ! "$MATCHER" =~ ^[A-Za-z0-9_|*\(\)\ ]+$ ]]; then
  add_err "**Matcher** \`$MATCHER\` contains unexpected characters. Stick to letters, digits, underscores and \`|\`."
fi

# Bypass: optional but if present must be CLAUDE_*.
if [[ -n "$BYPASS" ]] && [[ ! "$BYPASS" =~ ^CLAUDE_[A-Z0-9_]+$ ]]; then
  add_err "**Bypass env var** \`$BYPASS\` should match \`CLAUDE_[A-Z0-9_]+\`."
fi

# Description: must be non-empty (we use the first paragraph of "What it does").
if [[ -z "$DESCRIPTION" ]]; then
  add_err "**What it does** is empty — needed for the hook header."
fi

# Risk level: optional for parsing, but flag if blocking/privileged needs a bypass var.
case "$RISK" in
  *blocking*|*privileged*)
    if [[ -z "$BYPASS" ]]; then
      add_err "Risk level is **${RISK}** — please supply a **Bypass env var** so users can disable the hook in an emergency."
    fi
    ;;
esac

# ── emit ──────────────────────────────────────────────────────────────────────

if [[ -n "$ERRORS" ]]; then
  emit_output "valid" "false"
  emit_output "errors" "$ERRORS"
  exit 0
fi

emit_output "valid"       "true"
emit_output "name"        "$NAME"
emit_output "category"    "$CATEGORY"
emit_output "event"       "$EVENT"
emit_output "matcher"     "$MATCHER"
emit_output "description" "$DESCRIPTION"
emit_output "bypass"      "$BYPASS"
emit_output "style"       "$STYLE"
