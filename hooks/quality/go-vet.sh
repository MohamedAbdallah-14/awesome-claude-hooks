#!/usr/bin/env bash
# Hook name:   go-vet
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: After Claude writes a .go file, runs `go vet ./...` in the
#              package directory to catch common correctness issues, and runs
#              `gofmt -l` to check formatting. Optionally also runs the test
#              suite for the affected package.
#
#              Matches: .go
#
# Config (env vars):
#   CLAUDE_GO_TEST_ON_CHANGE=1   Also run `go test ./...` in the package
#                                directory after edits. Default: 0 (vet only).
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "PostToolUse": [
#         {
#           "matcher": "Write|Edit|MultiEdit",
#           "hooks": [
#             {
#               "type": "command",
#               "command": "/path/to/hooks/quality/go-vet.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[go-vet] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# ── extension filter ──────────────────────────────────────────────────────────

case "$FILE_PATH" in
  *.go) ;;
  *) exit 0 ;;
esac

# ── file must exist ───────────────────────────────────────────────────────────

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── go availability ───────────────────────────────────────────────────────────

if ! command -v go &>/dev/null; then
  echo "[go-vet] WARNING: go not found in PATH — skipping analysis for $FILE_PATH" >&2
  exit 0
fi

# ── locate package directory ──────────────────────────────────────────────────

PKG_DIR=$(dirname "$FILE_PATH")

# ── run go vet ────────────────────────────────────────────────────────────────

VET_OUTPUT=""
VET_EXIT=0
VET_OUTPUT=$(cd "$PKG_DIR" && go vet ./... 2>&1) || VET_EXIT=$?

# ── run gofmt -l ─────────────────────────────────────────────────────────────

FMT_OUTPUT=""
FMT_OUTPUT=$(gofmt -l "$FILE_PATH" 2>&1) || true

# ── report vet results ────────────────────────────────────────────────────────

if [[ $VET_EXIT -ne 0 ]]; then
  echo "[go-vet] go vet found issues in package $(basename "$PKG_DIR"):"
  echo "$VET_OUTPUT"
  echo ""
else
  echo "[go-vet] go vet — no issues in package $(basename "$PKG_DIR")"
fi

# ── report gofmt results ──────────────────────────────────────────────────────

if [[ -n "$FMT_OUTPUT" ]]; then
  echo "[go-vet] $FILE_PATH is not gofmt-formatted."
  echo "[go-vet] To fix: gofmt -w $FILE_PATH"
  echo ""
  # Show the actual diff
  if command -v diff &>/dev/null; then
    FORMATTED=$(gofmt "$FILE_PATH" 2>/dev/null) || true
    ORIGINAL=$(cat "$FILE_PATH")
    diff --unified=3 \
      <(printf '%s\n' "$ORIGINAL") \
      <(printf '%s\n' "$FORMATTED") \
      --label "current" \
      --label "gofmt" 2>/dev/null || true
  fi
else
  echo "[go-vet] gofmt — $FILE_PATH is correctly formatted"
fi

# ── optional: run tests ───────────────────────────────────────────────────────

if [[ "${CLAUDE_GO_TEST_ON_CHANGE:-0}" == "1" ]]; then
  echo ""
  echo "[go-vet] Running tests in package $(basename "$PKG_DIR") (CLAUDE_GO_TEST_ON_CHANGE=1)..."
  TEST_OUTPUT=""
  TEST_EXIT=0
  TEST_OUTPUT=$(cd "$PKG_DIR" && go test ./... 2>&1) || TEST_EXIT=$?

  if [[ $TEST_EXIT -eq 0 ]]; then
    echo "[go-vet] Tests passed:"
    echo "$TEST_OUTPUT"
  else
    echo "[go-vet] Tests FAILED:"
    echo "$TEST_OUTPUT"
  fi
fi

exit 0
