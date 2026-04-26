#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# lint-hooks.sh — enforce the hook contract documented in docs/hook-contract.md.
#
# Exits 0 if every hook passes; nonzero otherwise. Prints one diagnostic per
# offending file to stderr.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/hooks"

if ! command -v jq >/dev/null 2>&1; then
  echo "lint-hooks: jq is required" >&2
  exit 1
fi

# When running in GitHub Actions, also emit ::error annotations so failures
# show up inline on the PR diff.
emit_annotation() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    printf '::error file=%s::%s\n' "$1" "$2"
  fi
}

VALID_EVENTS='^(PreToolUse|PostToolUse|Stop|SubagentStop|PreCompact|SessionStart|Notification|UserPromptSubmit)( |$)'

errors=0
checked=0

fail() {
  local rel="$1" msg="$2"
  echo "$rel: $msg" >&2
  emit_annotation "$rel" "$msg"
  errors=$((errors + 1))
}

while IFS= read -r f; do
  checked=$((checked + 1))
  rel="${f#"$REPO_ROOT"/}"

  # Read the first 80 lines once.
  header=$(head -n 80 "$f")

  # 1. Shebang on line 1.
  if ! head -n 1 "$f" | grep -q '^#!/usr/bin/env bash$'; then
    fail "$rel" "missing or wrong shebang on line 1 (want '#!/usr/bin/env bash')"
  fi

  # 2. SPDX line.
  if ! grep -q '^# SPDX-License-Identifier: CC0-1.0$' <<<"$header"; then
    fail "$rel" "missing SPDX header line"
  fi

  # 3. Hook name matches filename.
  expected_name="$(basename "$f" .sh)"
  hook_name=$(grep -m1 '^# Hook name:' <<<"$header" | sed 's/^# Hook name:[[:space:]]*//' | xargs || true)
  if [[ -z "$hook_name" ]]; then
    fail "$rel" "missing '# Hook name:' header"
  elif [[ "$hook_name" != "$expected_name" ]]; then
    fail "$rel" "hook name '$hook_name' does not match filename '$expected_name'"
  fi

  # 4. Event header with valid event.
  event_line=$(grep -m1 '^# Event:' <<<"$header" | sed 's/^# Event:[[:space:]]*//' | xargs || true)
  if [[ -z "$event_line" ]]; then
    fail "$rel" "missing '# Event:' header"
  elif ! [[ "$event_line" =~ $VALID_EVENTS ]]; then
    fail "$rel" "'# Event: $event_line' is not a recognised Claude Code event"
  fi

  # 5. Description present.
  if ! grep -q '^# Description:' <<<"$header"; then
    fail "$rel" "missing '# Description:' header"
  fi

  # 6. set -euo pipefail.
  if ! grep -q '^set -euo pipefail' "$f"; then
    fail "$rel" "missing 'set -euo pipefail'"
  fi

  # 7. Install JSON snippet must parse. Extract the JSON-ish block from the
  # header comments by counting brace depth, and feed it to jq.
  install_block=$(awk '
    /^# Install/ { in_install = 1; next }
    in_install && !capturing && /^#[[:space:]]*\{/ { capturing = 1; depth = 0 }
    capturing {
      line = $0
      sub(/^#[[:space:]]?/, "", line)
      print line
      n_open = gsub(/\{/, "{", line)
      n_close = gsub(/\}/, "}", line)
      depth += n_open - n_close
      if (depth <= 0) { capturing = 0; in_install = 0; exit }
    }
  ' "$f")

  if [[ -n "$install_block" ]]; then
    if ! printf '%s\n' "$install_block" | jq empty >/dev/null 2>&1; then
      fail "$rel" "install snippet in header is not valid JSON"
    fi
  fi
done < <(find "$HOOKS_DIR" -mindepth 2 -name '*.sh' -type f -not -path '*/_lib/*' | sort)

if (( errors > 0 )); then
  echo "" >&2
  echo "lint-hooks: $errors error(s) across $checked hooks" >&2
  exit 1
fi

echo "lint-hooks: $checked hooks passed"
