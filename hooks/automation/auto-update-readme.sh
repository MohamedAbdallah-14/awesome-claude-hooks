#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# Hook name:   auto-update-readme
# Event:       PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: When Claude updates a manifest file (package.json, pubspec.yaml,
#              pyproject.toml, Cargo.toml), extracts the new version and updates
#              matching version references in README.md:
#
#                - Shields.io / img.shields.io version badges
#                  [![version](https://img.shields.io/badge/version-x.y.z-...)]
#                - Plain "version: x.y.z" or "version = "x.y.z"" lines
#
#              Only triggers for the four manifest file names listed above.
#              Skips silently if README.md is absent or contains no version refs.
#
# Config (env vars):
#   CLAUDE_AUTO_UPDATE_README=0   Set to 1 to enable (opt-in, default OFF).
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
#               "command": "/path/to/hooks/automation/auto-update-readme.sh"
#             }
#           ]
#         }
#       ]
#     }
#   }

set -euo pipefail

# ── opt-in gate ───────────────────────────────────────────────────────────────

if [[ "${CLAUDE_AUTO_UPDATE_README:-0}" != "1" ]]; then
  exit 0
fi

# ── dependency checks ─────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "[auto-update-readme] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi

# ── parse stdin ───────────────────────────────────────────────────────────────

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')

if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

FILE_BASE=$(basename "$FILE_PATH")

# ── manifest filter ───────────────────────────────────────────────────────────

case "$FILE_BASE" in
  package.json|pubspec.yaml|pyproject.toml|Cargo.toml) ;;
  *) exit 0 ;;
esac

FILE_DIR=$(dirname "$FILE_PATH")

# ── extract new version from manifest ────────────────────────────────────────

NEW_VERSION=""

case "$FILE_BASE" in
  package.json)
    if command -v jq &>/dev/null; then
      NEW_VERSION=$(jq -r '.version // ""' "$FILE_PATH" 2>/dev/null || true)
    fi
    ;;

  pubspec.yaml)
    # version: 1.2.3+4  →  take the part before '+'
    NEW_VERSION=$(grep -E '^version:' "$FILE_PATH" 2>/dev/null \
      | head -1 \
      | sed 's/^version:[[:space:]]*//' \
      | sed 's/+.*//' \
      | tr -d '[:space:]"'"'"'' || true)
    ;;

  pyproject.toml)
    # PEP 621: version = "x.y.z"
    NEW_VERSION=$(grep -E '^version[[:space:]]*=' "$FILE_PATH" 2>/dev/null \
      | head -1 \
      | sed 's/.*=[[:space:]]*//' \
      | tr -d '[:space:]"'"'"'' || true)
    ;;

  Cargo.toml)
    # version = "x.y.z" (only in [package] section — grab first occurrence)
    NEW_VERSION=$(grep -E '^version[[:space:]]*=' "$FILE_PATH" 2>/dev/null \
      | head -1 \
      | sed 's/.*=[[:space:]]*//' \
      | tr -d '[:space:]"'"'"'' || true)
    ;;
esac

if [[ -z "$NEW_VERSION" || "$NEW_VERSION" == "null" ]]; then
  echo "[auto-update-readme] Could not extract version from $FILE_BASE — skipping"
  exit 0
fi

# basic semver-ish sanity check
if ! printf '%s' "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?'; then
  echo "[auto-update-readme] Extracted version '$NEW_VERSION' does not look like semver — skipping"
  exit 0
fi

# ── find README.md ────────────────────────────────────────────────────────────

README_PATH=""
# look in same dir first, then project root
for candidate in "$FILE_DIR/README.md" "$FILE_DIR/../README.md"; do
  REAL=$(realpath "$candidate" 2>/dev/null || true)
  if [[ -n "$REAL" && -f "$REAL" ]]; then
    README_PATH="$REAL"
    break
  fi
done

# also try git root
if [[ -z "$README_PATH" ]]; then
  REPO_ROOT=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/README.md" ]]; then
    README_PATH="$REPO_ROOT/README.md"
  fi
fi

if [[ -z "$README_PATH" ]]; then
  echo "[auto-update-readme] No README.md found near $FILE_PATH — skipping"
  exit 0
fi

# ── check for version references in README ───────────────────────────────────

# Match patterns:
#   1. Shields.io badge URLs: /badge/version-1.2.3- or /badge/v1.2.3-
#   2. img.shields.io/badge/<label>-<version>-<color>
#   3. Plain  "version: x.y.z"  or  "version = x.y.z"  or  "version x.y.z"

VERSION_PATTERN='[0-9]+\.[0-9]+(\.[0-9]+)?'

if ! grep -qE "(badge/v?${VERSION_PATTERN}|version[[:space:]]*[:=][[:space:]]*${VERSION_PATTERN})" "$README_PATH" 2>/dev/null; then
  echo "[auto-update-readme] No version references found in $README_PATH — skipping"
  exit 0
fi

# ── perform replacements ──────────────────────────────────────────────────────

TEMP_FILE=$(mktemp)
cp "$README_PATH" "$TEMP_FILE"

# 1. Shields.io badge: badge/version-OLD- or badge/v-OLD-
sed -E "s|(badge/v?)[0-9]+\.[0-9]+(\.[0-9]+)?-|\1${NEW_VERSION}-|g" "$TEMP_FILE" > "${TEMP_FILE}.new"
mv "${TEMP_FILE}.new" "$TEMP_FILE"

# 2. Plain "version: x.y.z" or "version = x.y.z" (case-insensitive label)
sed -E "s|(version[[:space:]]*[:=][[:space:]]*)[0-9]+\.[0-9]+(\.[0-9]+)?|\1${NEW_VERSION}|g" "$TEMP_FILE" > "${TEMP_FILE}.new"
mv "${TEMP_FILE}.new" "$TEMP_FILE"

# ── only write if something changed ──────────────────────────────────────────

if diff -q "$README_PATH" "$TEMP_FILE" &>/dev/null; then
  echo "[auto-update-readme] README.md already references version $NEW_VERSION — no changes needed"
  rm -f "$TEMP_FILE"
  exit 0
fi

cp "$TEMP_FILE" "$README_PATH"
rm -f "$TEMP_FILE"

echo "[auto-update-readme] Updated $README_PATH to version $NEW_VERSION (from $FILE_BASE)"

exit 0
