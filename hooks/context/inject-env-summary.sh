#!/usr/bin/env bash
# Hook name:   inject-env-summary
# Event:       Stop
# Description: After each response, writes a safe environment snapshot to
#              ~/.claude/context/env-summary.md covering tool versions,
#              OS details, Docker state, and git remote.
#
#              Security note: this hook NEVER reads or emits env var VALUES.
#              It only lists the names of non-empty env vars in the shell
#              environment, so secrets stay out of Claude's context.
#
# Config (env vars):
#   CLAUDE_ENV_SUMMARY_INCLUDE_VERSIONS   Set to 0 to skip version checks
#                                         (useful on slow machines). Default: 1.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "Stop": [
#         {
#           "matcher": "",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/context/inject-env-summary.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[inject-env-summary] WARNING: jq not found — skipping" >&2
  exit 0
fi

# ── config ────────────────────────────────────────────────────────────────────

INCLUDE_VERSIONS="${CLAUDE_ENV_SUMMARY_INCLUDE_VERSIONS:-1}"
CONTEXT_DIR="${HOME}/.claude/context"
OUTPUT_FILE="${CONTEXT_DIR}/env-summary.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)
if ! printf '%s' "$INPUT" | jq -e . &>/dev/null; then
  echo "[inject-env-summary] WARNING: invalid JSON on stdin — skipping" >&2
  exit 0
fi

# ── helpers ───────────────────────────────────────────────────────────────────

# Safely get a tool version; returns "not installed" if absent
tool_version() {
  local cmd="$1"
  local version_flag="${2:---version}"
  if command -v "$cmd" &>/dev/null; then
    "$cmd" "$version_flag" 2>&1 | head -1 | tr -d '\n' || echo "installed (version unknown)"
  else
    echo "not installed"
  fi
}

# ── gather data ───────────────────────────────────────────────────────────────

OS_NAME=$(uname -s)
OS_ARCH=$(uname -m)
OS_VERSION=$(uname -r)

mkdir -p "$CONTEXT_DIR"

{
  printf '# Environment Summary\n\n'
  printf '_Updated: %s_\n\n' "$TIMESTAMP"

  printf '## System\n\n'
  printf '| Key | Value |\n|-----|-------|\n'
  printf '| OS | %s |\n' "$OS_NAME"
  printf '| Architecture | %s |\n' "$OS_ARCH"
  printf '| Kernel | %s |\n' "$OS_VERSION"

  # macOS: pretty name
  if [[ "$OS_NAME" == "Darwin" ]]; then
    if command -v sw_vers &>/dev/null; then
      MACOS_VER=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
      printf '| macOS version | %s |\n' "$MACOS_VER"
    fi
  fi

  # Linux: distro
  if [[ -f /etc/os-release ]]; then
    DISTRO=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"' || echo "unknown")
    printf '| Distribution | %s |\n' "$DISTRO"
  fi

  printf '\n'

  if [[ "$INCLUDE_VERSIONS" == "1" ]]; then
    printf '## Tool Versions\n\n'
    printf '| Tool | Version |\n|------|--------|\n'

    # Node.js
    NODE_VER=$(tool_version node --version)
    printf '| Node.js | %s |\n' "$NODE_VER"

    # npm
    if command -v npm &>/dev/null; then
      NPM_VER=$(npm --version 2>/dev/null || echo "unknown")
      printf '| npm | %s |\n' "$NPM_VER"
    fi

    # Python
    PYTHON_VER="not installed"
    if command -v python3 &>/dev/null; then
      PYTHON_VER=$(python3 --version 2>&1 | head -1)
    elif command -v python &>/dev/null; then
      PYTHON_VER=$(python --version 2>&1 | head -1)
    fi
    printf '| Python | %s |\n' "$PYTHON_VER"

    # Go
    GO_VER=$(tool_version go version)
    printf '| Go | %s |\n' "$GO_VER"

    # Flutter
    FLUTTER_VER="not installed"
    if command -v flutter &>/dev/null; then
      FLUTTER_VER=$(flutter --version 2>/dev/null | head -1 || echo "installed (version check failed)")
    fi
    printf '| Flutter | %s |\n' "$FLUTTER_VER"

    # Dart
    DART_VER=$(tool_version dart --version)
    printf '| Dart | %s |\n' "$DART_VER"

    # Rust
    RUST_VER=$(tool_version rustc --version)
    printf '| Rust | %s |\n' "$RUST_VER"

    # Java
    JAVA_VER="not installed"
    if command -v java &>/dev/null; then
      JAVA_VER=$(java -version 2>&1 | head -1 || echo "installed")
    fi
    printf '| Java | %s |\n' "$JAVA_VER"

    # Git
    GIT_VER=$(tool_version git --version)
    printf '| Git | %s |\n' "$GIT_VER"

    printf '\n'
  fi

  # ── Docker ──────────────────────────────────────────────────────────────────
  printf '## Docker\n\n'
  if ! command -v docker &>/dev/null; then
    printf 'Docker not installed.\n\n'
  else
    DOCKER_VERSION=$(docker --version 2>/dev/null || echo "installed (version unknown)")
    printf '**Version:** %s\n\n' "$DOCKER_VERSION"

    # Check if daemon is running (docker info fails if daemon is down)
    if docker info &>/dev/null 2>&1; then
      CONTAINER_COUNT=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
      printf '**Daemon:** running\n'
      printf '**Running containers:** %s\n\n' "$CONTAINER_COUNT"
    else
      printf '**Daemon:** not running\n\n'
    fi
  fi

  # ── Git remote ──────────────────────────────────────────────────────────────
  printf '## Git Remote (origin)\n\n'
  if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "(no origin remote)")
    printf '`%s`\n\n' "$REMOTE_URL"
  else
    printf 'Not a git repository.\n\n'
  fi

  # ── Env var names (no values) ────────────────────────────────────────────────
  printf '## Set Environment Variable Names\n\n'
  printf '_Values are intentionally omitted for security._\n\n'
  printf '```\n'
  # List non-empty variable names, sorted, excluding common safe/known ones that
  # clutter the list (PATH, HOME, USER, SHELL, TERM, etc.)
  env | grep -v '^#' | cut -d= -f1 | sort | grep -vE \
    '^(PATH|HOME|USER|SHELL|TERM|LANG|PWD|OLDPWD|SHLVL|_|LOGNAME|DISPLAY|COLORTERM|TERM_PROGRAM|ITERM_SESSION_ID|PAGER|EDITOR|VISUAL|MANPATH|TMPDIR|TEMPDIR)$' \
    || true
  printf '```\n'
} > "$OUTPUT_FILE"

exit 0
