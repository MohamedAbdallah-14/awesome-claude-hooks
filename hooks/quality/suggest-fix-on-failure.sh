#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   suggest-fix-on-failure
# Event:       PostToolUseFailure (matcher: "Bash")
# Description: When a Bash tool call fails, look at the command + error
#              and surface a one-line hint Claude can act on
#              (missing dep, wrong cwd, lockfile drift, port in use, etc.).
#              Generic across npm / pnpm / yarn / pip / uv / poetry / cargo /
#              go / bundler / make / pytest / jest. Pure pattern matching —
#              no network, no LLM call, deterministic.
#
#              Returns Style B JSON with `additionalContext` so Claude
#              sees the hint on its next turn. Never blocks.
#
# Platforms: macos, linux, wsl. Pure regex over command + error strings;
#            no platform-specific dependencies.
#
# Config (env vars):
#   CLAUDE_SUGGEST_FIX_OFF=1   Disable this hook (bypass).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUseFailure": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/quality/suggest-fix-on-failure.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "[suggest-fix-on-failure] WARNING: jq not found — install it (brew install jq / apt-get install jq)" >&2
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_SUGGEST_FIX_OFF:-0}" == "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
ERROR=$(printf '%s' "$INPUT" | jq -r '.error // ""')

if [[ -z "$COMMAND" && -z "$ERROR" ]]; then
  exit 0
fi

# Combine command + error for pattern scanning. Cap to 8 KB so massive
# stack traces don't blow up grep. Done with bash parameter expansion (no
# pipe to `head`) so a large $ERROR can't trip pipefail/EPIPE under
# `set -euo pipefail` — the very case the cap exists to defend against.
HAYSTACK="${COMMAND}"$'\n'"${ERROR}"
HAYSTACK="${HAYSTACK:0:8192}"

# ── pattern-based hints ───────────────────────────────────────────────────────
# Each rule: a regex on $HAYSTACK and a hint to surface.
# First match wins. Order matters — most specific patterns first.

HINT=""

match() {
  printf '%s' "$HAYSTACK" | grep -qiE "$1"
}

# Node / npm / pnpm / yarn
if [[ -z "$HINT" ]] && match 'ENOENT.*package\.json|no such file.*package\.json'; then
  HINT="package.json not found in cwd. Run from the project root or 'cd' into the package directory before retrying."
elif [[ -z "$HINT" ]] && match 'ERESOLVE|peer dep.*could not be resolved|peer dependency'; then
  HINT="npm peer-dep conflict. Try 'npm install --legacy-peer-deps' or update the conflicting package's range."
elif [[ -z "$HINT" ]] && match 'EACCES.*npm|permission denied.*node_modules'; then
  HINT="Permission error in node_modules. Don't 'sudo npm' — fix ownership: 'sudo chown -R \$(id -un) ./node_modules' or use a node version manager."
elif [[ -z "$HINT" ]] && match 'cannot find module|MODULE_NOT_FOUND|Error \[ERR_MODULE_NOT_FOUND\]'; then
  HINT="Missing node module. Run 'npm install' (or pnpm/yarn) before re-running this command."
elif [[ -z "$HINT" ]] && match 'lockfile.*out of sync|frozen-lockfile.*mismatch|EUSAGE.*lockfile'; then
  HINT="Lockfile is out of sync with package.json. Run 'npm install' (or 'pnpm install --no-frozen-lockfile') to regenerate."

# Python / pip / uv / poetry
elif [[ -z "$HINT" ]] && match 'ModuleNotFoundError|No module named'; then
  MODULE=$(printf '%s' "$ERROR" | grep -oE "No module named ['\"][^'\"]+['\"]" | head -1 || true)
  if [[ -n "$MODULE" ]]; then
    HINT="Python ${MODULE}. Install it (pip/uv/poetry) or activate the right virtualenv before retrying."
  else
    HINT="Python ModuleNotFoundError. Install the missing package (pip/uv/poetry) or activate the right virtualenv."
  fi
elif [[ -z "$HINT" ]] && match 'externally-managed-environment'; then
  HINT="System Python is externally managed (PEP 668). Use a virtualenv: 'python -m venv .venv && source .venv/bin/activate'."
elif [[ -z "$HINT" ]] && match 'pyproject\.toml.*not found|could not find a pyproject\.toml'; then
  HINT="pyproject.toml not found. Run from the project root or 'cd' into the package."

# Cargo / Rust
elif [[ -z "$HINT" ]] && match 'could not find `Cargo\.toml`|no such file or directory.*Cargo\.toml'; then
  HINT="Cargo.toml not found. Run from the crate root or pass --manifest-path."
elif [[ -z "$HINT" ]] && match 'unresolved import|use of undeclared crate'; then
  HINT="Rust unresolved crate. Add it to Cargo.toml under [dependencies] or run 'cargo add <crate>'."

# Go
elif [[ -z "$HINT" ]] && match 'go\.mod file not found|cannot find main module'; then
  HINT="go.mod not found. Run from the module root or run 'go mod init' first."
elif [[ -z "$HINT" ]] && match 'missing go\.sum entry'; then
  HINT="go.sum is stale. Run 'go mod tidy' to refresh."

# Ruby / bundler
elif [[ -z "$HINT" ]] && match 'Could not locate Gemfile|no gemfile found'; then
  HINT="Gemfile not found. Run from the app root."
elif [[ -z "$HINT" ]] && match 'Bundler::GemNotFound|cannot load such file'; then
  HINT="Missing Ruby gem. Run 'bundle install' before retrying."

# Generic — port already in use
elif [[ -z "$HINT" ]] && match 'EADDRINUSE|address already in use|port.*already in use|listen tcp.*bind: address already in use'; then
  PORT=$(printf '%s' "$ERROR" | grep -oE ':[0-9]{2,5}' | head -1 | tr -d ':' || true)
  if [[ -n "$PORT" ]]; then
    HINT="Port ${PORT} is already in use. Find the offender: 'lsof -i :${PORT}' (macOS/Linux) or 'netstat -ano | findstr ${PORT}' (Windows), then kill it or pick a different port."
  else
    HINT="Port already in use. Find the offender with 'lsof -i :<port>' and kill it, or pick a different port."
  fi

# Generic — command not found
elif [[ -z "$HINT" ]] && match 'command not found|: not found$|is not recognized as an internal or external command'; then
  MISSING=$(printf '%s' "$ERROR" | grep -oE '[[:alnum:]_.+-]+: command not found' | head -1 | sed 's/: command not found//' || true)
  if [[ -n "$MISSING" ]]; then
    HINT="Binary '${MISSING}' is not on PATH. Install it or check your PATH/virtualenv before retrying."
  else
    HINT="A binary referenced in this command is not on PATH. Install it or check PATH/virtualenv."
  fi

# Generic — permission denied
elif [[ -z "$HINT" ]] && match 'permission denied|EACCES'; then
  HINT="Permission denied. Check file ownership / mode. Avoid 'sudo' inside a project — fix the underlying permission instead."

# Generic — connection refused (often dev DB / docker)
elif [[ -z "$HINT" ]] && match 'connection refused|ECONNREFUSED'; then
  HINT="Connection refused. Is the service (DB, redis, docker) running? Check 'docker ps' / your service manager."

# Tests failing (pytest / jest / vitest / mocha / go test)
elif [[ -z "$HINT" ]] && match '([0-9]+) failed|FAIL +[^ ]+|Tests:.*[0-9]+ failed|--- FAIL:'; then
  HINT="Tests failed. Re-run a single failing test in isolation to iterate faster, then fix the assertion (don't loosen it without justification)."

# Git
elif [[ -z "$HINT" ]] && match 'fatal: not a git repository'; then
  HINT="Not in a git repo. 'cd' into one or 'git init' first."
elif [[ -z "$HINT" ]] && match 'merge conflict|CONFLICT \(content\)'; then
  HINT="Merge conflicts present. Resolve them, 'git add' the resolved files, then continue (rebase --continue / commit)."

# Disk
elif [[ -z "$HINT" ]] && match 'no space left on device|ENOSPC'; then
  HINT="Out of disk space. Check 'df -h' and clean caches (npm/yarn/cargo/docker) before retrying."

fi

# ── decision ──────────────────────────────────────────────────────────────────

if [[ -z "$HINT" ]]; then
  exit 0
fi

jq -n --arg ctx "Hint from suggest-fix-on-failure: ${HINT}" '
  {
    hookSpecificOutput: {
      hookEventName: "PostToolUseFailure",
      additionalContext: $ctx
    }
  }
'
exit 0
