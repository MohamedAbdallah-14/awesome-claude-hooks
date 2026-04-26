#!/usr/bin/env bash
# Hook name:   pr-description-gen
# Event:       PostToolUse (matcher: "Bash")
# Description: After a gh pr create or git push command, collects the commit
#              list and diff summary for commits on this branch vs the base
#              branch. Outputs the data as context so Claude has everything
#              it needs to write or improve a PR description.
#
#              Triggers when the tool response stdout contains a GitHub PR URL
#              (github.com/.../pull/) OR when the command is gh pr create.
#
#              Gathers:
#                git log <base>..HEAD --oneline   — one line per commit
#                git diff <base>...HEAD --stat     — files changed summary
#                gh pr view --json url,title,body  — current PR metadata
#
# Config (env vars):
#   CLAUDE_PR_AUTO_DESCRIBE=1     Enable the hook. Default: 1.
#   CLAUDE_PR_BASE_BRANCH         Override base branch for log/diff.
#                                 Default: auto-detected from git or "main".
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Bash",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/git/pr-description-gen.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[pr-description-gen] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

if ! command -v git &>/dev/null; then
  exit 0
fi

# ── bypass flag ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_PR_AUTO_DESCRIBE:-1}" != "1" ]]; then
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // ""')
STDERR=$(printf '%s' "$INPUT" | jq -r '.tool_response.stderr // ""')

# ── filter: only fire on PR-creating commands ─────────────────────────────────

IS_PR_CREATE=0

# Explicit gh pr create
if printf '%s' "$COMMAND" | grep -qE '^\s*gh\s+pr\s+create\b'; then
  IS_PR_CREATE=1
fi

# git push that produced a PR URL in stdout or stderr (GitHub's "Create a pull request" link)
if [[ "$IS_PR_CREATE" == "0" ]]; then
  COMBINED="${STDOUT}
${STDERR}"
  if printf '%s' "$COMBINED" | grep -qE 'github\.com/[^/]+/[^/]+/pull/[0-9]+'; then
    IS_PR_CREATE=1
  fi
fi

if [[ "$IS_PR_CREATE" == "0" ]]; then
  exit 0
fi

# ── git repo check ────────────────────────────────────────────────────────────

if ! git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  exit 0
fi

# ── determine base branch ─────────────────────────────────────────────────────

if [[ -n "${CLAUDE_PR_BASE_BRANCH:-}" ]]; then
  BASE="${CLAUDE_PR_BASE_BRANCH}"
else
  # Try to detect from gh pr view, then fall back to common defaults
  BASE=""
  if command -v gh &>/dev/null; then
    BASE=$(gh pr view --json baseRefName --jq '.baseRefName' 2>/dev/null || echo "")
  fi
  if [[ -z "$BASE" ]]; then
    # Check which common base branches exist
    for candidate in main master develop trunk; do
      if git show-ref --quiet "refs/heads/${candidate}" 2>/dev/null \
         || git show-ref --quiet "refs/remotes/origin/${candidate}" 2>/dev/null; then
        BASE="$candidate"
        break
      fi
    done
  fi
  BASE="${BASE:-main}"
fi

CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "unknown")

# ── gather commit log ─────────────────────────────────────────────────────────

# Use three-dot range (symmetric difference base) for accurate branch-only commits
COMMIT_LOG=$(git log "${BASE}..HEAD" --oneline 2>/dev/null || true)
COMMIT_COUNT=$(printf '%s' "$COMMIT_LOG" | grep -c . || echo "0")

if [[ -z "$COMMIT_LOG" ]]; then
  COMMIT_LOG="(no commits found ahead of ${BASE})"
fi

# ── gather diff stat ──────────────────────────────────────────────────────────

DIFF_STAT=$(git diff "${BASE}...HEAD" --stat 2>/dev/null | tail -20 || true)
if [[ -z "$DIFF_STAT" ]]; then
  DIFF_STAT="(no diff stat available)"
fi

# ── get PR URL from stdout/stderr ─────────────────────────────────────────────

PR_URL=""
COMBINED_OUTPUT="${STDOUT}
${STDERR}"
PR_URL=$(printf '%s' "$COMBINED_OUTPUT" | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1 || echo "")

# ── fetch current PR metadata via gh (if available) ──────────────────────────

PR_META=""
if command -v gh &>/dev/null && [[ -n "$PR_URL" ]]; then
  PR_META=$(gh pr view "$PR_URL" --json title,body,additions,deletions,changedFiles \
    --jq '"Title: \(.title)\nChanged files: \(.changedFiles)  +\(.additions) -\(.deletions)"' \
    2>/dev/null || echo "")
fi

# ── build context output ──────────────────────────────────────────────────────

{
  printf 'PR created on branch: %s → %s\n' "$CURRENT_BRANCH" "$BASE"
  [[ -n "$PR_URL" ]]  && printf 'PR URL: %s\n' "$PR_URL"
  [[ -n "$PR_META" ]] && printf '%s\n' "$PR_META"
  printf '\n'
  printf '## Commits in this PR (%s total)\n\n' "$COMMIT_COUNT"
  printf '%s\n' "$COMMIT_LOG"
  printf '\n'
  printf '## Files changed (diff stat vs %s)\n\n' "$BASE"
  printf '%s\n' "$DIFF_STAT"
} | jq -Rs '{"context": .}'

exit 0
