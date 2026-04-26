#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# new-hook.sh — interactive scaffold for a new hook conforming to docs/hook-contract.md.
#
# Usage:
#   bash scripts/new-hook.sh
#   bash scripts/new-hook.sh --name=my-hook --category=security \
#       --event=PreToolUse --matcher='Write|Edit' \
#       --description='Catches X' --bypass=CLAUDE_ALLOW_X --style=B
#
# Flags override interactive prompts. Missing flags fall through to a prompt.
# Style A: stderr + exit 2. Style B: stdout JSON + exit 0.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/hooks"
TESTS_DIR="${REPO_ROOT}/tests"

# ── deps ──────────────────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "new-hook: jq is required (brew install jq)" >&2
  exit 1
fi

# ── valid event list (must mirror scripts/lint-hooks.sh VALID_EVENTS) ─────────

VALID_EVENTS="SessionStart UserPromptSubmit UserPromptExpansion PreToolUse PermissionRequest PermissionDenied PostToolUse PostToolUseFailure PostToolBatch Notification SubagentStart SubagentStop TaskCreated TaskCompleted Stop StopFailure TeammateIdle InstructionsLoaded ConfigChange CwdChanged FileChanged WorktreeCreate WorktreeRemove PreCompact PostCompact Elicitation ElicitationResult SessionEnd"

is_valid_event() {
  local needle="$1" e
  for e in $VALID_EVENTS; do
    if [[ "$e" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

is_valid_category() {
  local cat="$1"
  [[ -d "${HOOKS_DIR}/${cat}" ]]
}

is_kebab_case() {
  [[ "$1" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]]
}

# ── arg parse ─────────────────────────────────────────────────────────────────

NAME=""
CATEGORY=""
EVENT=""
MATCHER=""
DESCRIPTION=""
BYPASS=""
STYLE=""

for arg in "$@"; do
  case "$arg" in
    --name=*)        NAME="${arg#*=}" ;;
    --category=*)    CATEGORY="${arg#*=}" ;;
    --event=*)       EVENT="${arg#*=}" ;;
    --matcher=*)     MATCHER="${arg#*=}" ;;
    --description=*) DESCRIPTION="${arg#*=}" ;;
    --bypass=*)      BYPASS="${arg#*=}" ;;
    --style=*)       STYLE="${arg#*=}" ;;
    -h|--help)
      sed -n '4,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "new-hook: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

prompt() {
  # prompt <varname> <message> [default]
  local var="$1" msg="$2" default="${3:-}" current val
  eval "current=\${$var}"
  if [[ -n "$current" ]]; then
    return 0
  fi
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$msg" "$default" >&2
  else
    printf '%s: ' "$msg" >&2
  fi
  IFS= read -r val || val=""
  if [[ -z "$val" && -n "$default" ]]; then
    val="$default"
  fi
  eval "$var=\$val"
}

prompt NAME        "Hook name (kebab-case)"
if ! is_kebab_case "$NAME"; then
  echo "new-hook: name '$NAME' is not kebab-case (lowercase letters, digits, hyphens; must start with a letter)" >&2
  exit 1
fi

prompt CATEGORY    "Category (existing dir under hooks/)"
if ! is_valid_category "$CATEGORY"; then
  echo "new-hook: category '$CATEGORY' is not an existing directory under hooks/" >&2
  echo "  available:" >&2
  for d in "$HOOKS_DIR"/*/; do
    [[ -d "$d" ]] && echo "    $(basename "$d")" >&2
  done
  exit 1
fi

prompt EVENT       "Event (one of the 28 listed in docs/hook-contract.md)"
if ! is_valid_event "$EVENT"; then
  echo "new-hook: event '$EVENT' is not in the supported list" >&2
  echo "  valid: $VALID_EVENTS" >&2
  exit 1
fi

prompt MATCHER     "Matcher (optional, e.g. 'Write|Edit'; press Enter for none)"
prompt DESCRIPTION "One-line description"
prompt BYPASS      "Bypass env var name (e.g. CLAUDE_ALLOW_X; press Enter for none)"
prompt STYLE       "Signaling style (A=stderr+exit2, B=stdout JSON+exit0)" "B"

STYLE="$(printf '%s' "$STYLE" | tr '[:lower:]' '[:upper:]')"
if [[ "$STYLE" != "A" && "$STYLE" != "B" ]]; then
  echo "new-hook: style must be A or B (got '$STYLE')" >&2
  exit 1
fi

if [[ -z "$DESCRIPTION" ]]; then
  echo "new-hook: description is required" >&2
  exit 1
fi

# ── target paths ──────────────────────────────────────────────────────────────

HOOK_PATH="${HOOKS_DIR}/${CATEGORY}/${NAME}.sh"
TEST_PATH="${TESTS_DIR}/${CATEGORY}/${NAME}.bats"

if [[ -e "$HOOK_PATH" ]]; then
  echo "new-hook: refusing to overwrite existing hook: $HOOK_PATH" >&2
  exit 1
fi
if [[ -e "$TEST_PATH" ]]; then
  echo "new-hook: refusing to overwrite existing test: $TEST_PATH" >&2
  exit 1
fi

mkdir -p "${TESTS_DIR}/${CATEGORY}"

# ── header pieces ─────────────────────────────────────────────────────────────

if [[ -n "$MATCHER" ]]; then
  EVENT_LINE="${EVENT} (matcher: \"${MATCHER}\")"
else
  EVENT_LINE="${EVENT}"
fi

# Build install JSON via jq so the linter's jq-empty parse always passes.
if [[ -n "$MATCHER" ]]; then
  INSTALL_JSON=$(jq -n \
    --arg event "$EVENT" \
    --arg matcher "$MATCHER" \
    --arg cmd "/path/to/hooks/${CATEGORY}/${NAME}.sh" \
    '{hooks: {($event): [{matcher: $matcher, hooks: [{type: "command", command: $cmd}]}]}}')
else
  INSTALL_JSON=$(jq -n \
    --arg event "$EVENT" \
    --arg cmd "/path/to/hooks/${CATEGORY}/${NAME}.sh" \
    '{hooks: {($event): [{hooks: [{type: "command", command: $cmd}]}]}}')
fi

# Indent each line with "#   " for the comment header.
INSTALL_BLOCK=$(printf '%s\n' "$INSTALL_JSON" | sed 's/^/#   /')

# Optional config-vars header chunk.
if [[ -n "$BYPASS" ]]; then
  CONFIG_BLOCK=$(printf '#\n# Config (env vars):\n#   %s=1   Disable this hook (bypass).\n' "$BYPASS")
else
  CONFIG_BLOCK=""
fi

# ── style-specific bodies ─────────────────────────────────────────────────────

if [[ "$STYLE" == "A" ]]; then
  STYLE_BODY=$(cat <<'EOF'
# ── decision (Style A: stderr + exit 2 hard block) ────────────────────────────
# Replace the condition below with your real check.
# Example:
#   if [[ "$TOOL_NAME" == "Bash" ]] && printf '%s' "$INPUT" | jq -e '.tool_input.command | test("rm -rf /")' >/dev/null; then
#     echo "Blocked: rm -rf / detected." >&2
#     exit 2
#   fi

# TODO: implement check.

exit 0
EOF
)
else
  # Style B body depends on event family for the right output shape.
  case "$EVENT" in
    PreToolUse)
      STYLE_BODY=$(cat <<'EOF'
# ── decision (Style B: stdout JSON, exit 0) ───────────────────────────────────
# TODO: implement your check. Emit a deny decision when the rule trips.
#
# Example:
#   if printf '%s' "$INPUT" | jq -e '.tool_input.content | test("FORBIDDEN")' >/dev/null; then
#     jq -n --arg reason "Blocked: forbidden token detected." '{
#       hookSpecificOutput: {
#         hookEventName: "PreToolUse",
#         permissionDecision: "deny",
#         permissionDecisionReason: $reason
#       }
#     }'
#     exit 0
#   fi

exit 0
EOF
)
      ;;
    PostToolUse|PostToolUseFailure|PostToolBatch)
      STYLE_BODY=$(cat <<'EOF'
# ── decision (Style B: stdout JSON, exit 0) ───────────────────────────────────
# TODO: implement your check. To block + give Claude context after the tool ran:
#
#   jq -n --arg reason "..." --arg ctx "..." '{
#     decision: "block",
#     reason: $reason,
#     hookSpecificOutput: {
#       hookEventName: "PostToolUse",
#       additionalContext: $ctx
#     }
#   }'
#   exit 0

exit 0
EOF
)
      ;;
    SessionStart|UserPromptSubmit|UserPromptExpansion|InstructionsLoaded)
      STYLE_BODY=$(cat <<EOF
# ── decision (Style B: stdout JSON, exit 0) ───────────────────────────────────
# TODO: build the context string you want to inject.
#
# CONTEXT="hello from ${NAME}"
# jq -n --arg ctx "\$CONTEXT" '{
#   hookSpecificOutput: {
#     hookEventName: "${EVENT}",
#     additionalContext: \$ctx
#   }
# }'
# exit 0

exit 0
EOF
)
      ;;
    *)
      STYLE_BODY=$(cat <<EOF
# ── decision (Style B: stdout JSON, exit 0) ───────────────────────────────────
# TODO: emit any universal fields you need (continue, stopReason, suppressOutput,
# systemMessage) or hookSpecificOutput keyed on hookEventName="${EVENT}".

exit 0
EOF
)
      ;;
  esac
fi

# Bypass block (only if user supplied an env var name).
if [[ -n "$BYPASS" ]]; then
  BYPASS_BLOCK=$(cat <<EOF
# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "\${${BYPASS}:-0}" == "1" ]]; then
  exit 0
fi

EOF
)
else
  BYPASS_BLOCK=""
fi

# ── write the hook ────────────────────────────────────────────────────────────

{
  printf '#!/usr/bin/env bash\n'
  printf '# SPDX-License-Identifier: CC0-1.0\n'
  printf '# Hook name:   %s\n' "$NAME"
  printf '# Event:       %s\n' "$EVENT_LINE"
  printf '# Description: %s\n' "$DESCRIPTION"
  if [[ -n "$CONFIG_BLOCK" ]]; then
    printf '%s\n' "$CONFIG_BLOCK"
  fi
  printf '#\n'
  printf '# Install — add to ~/.claude/settings.json (or project .claude/settings.json):\n'
  printf '#\n'
  printf '%s\n' "$INSTALL_BLOCK"
  printf '\n'
  printf 'set -euo pipefail\n'
  printf '\n'
  printf '# ── dependency check ──────────────────────────────────────────────────────────\n'
  printf '\n'
  printf 'if ! command -v jq >/dev/null 2>&1; then\n'
  printf '  echo "[%s] WARNING: jq not found — install it (brew install jq / apt-get install jq)" >&2\n' "$NAME"
  printf '  exit 0\n'
  printf 'fi\n'
  printf '\n'
  if [[ -n "$BYPASS_BLOCK" ]]; then
    printf '%s\n' "$BYPASS_BLOCK"
  fi
  printf '# ── parse stdin ───────────────────────────────────────────────────────────────\n'
  printf '\n'
  printf 'INPUT=$(cat)\n'
  printf '%s\n' 'TOOL_NAME=$(printf %s "$INPUT" | jq -r '"'"'.tool_name // ""'"'"')'
  printf '\n'
  printf '# Silence shellcheck if TOOL_NAME is unused in your initial stub.\n'
  printf ': "${TOOL_NAME:-}"\n'
  printf '\n'
  printf '%s\n' "$STYLE_BODY"
} > "$HOOK_PATH"

chmod +x "$HOOK_PATH"

# ── write the test ────────────────────────────────────────────────────────────

cat > "$TEST_PATH" <<EOF
#!/usr/bin/env bats
# SPDX-License-Identifier: CC0-1.0

load '../test_helper'

HOOK="\${HOOKS_DIR}/${CATEGORY}/${NAME}.sh"

@test "${NAME}: hook file is executable" {
  [ -x "\$HOOK" ]
}
EOF

# ── verify ────────────────────────────────────────────────────────────────────

echo ""
echo "Created:"
echo "  $HOOK_PATH"
echo "  $TEST_PATH"
echo ""

echo "Running scripts/lint-hooks.sh ..."
if bash "${REPO_ROOT}/scripts/lint-hooks.sh"; then
  echo "lint: OK"
else
  echo "lint: FAILED" >&2
  exit 1
fi

if command -v bats >/dev/null 2>&1; then
  echo "Running bats on the new test ..."
  if bats "$TEST_PATH"; then
    echo "bats: OK"
  else
    echo "bats: FAILED" >&2
    exit 1
  fi
else
  echo "bats not installed — skipping test run"
fi

echo ""
echo "Done. Edit $HOOK_PATH to implement the check, then expand $TEST_PATH."
