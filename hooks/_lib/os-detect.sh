#!/usr/bin/env bash
# SPDX-License-Identifier: CC0-1.0
# os-detect.sh — sourced by hooks that need to branch on OS.
#
# Usage:
#   source "$(dirname "$0")/../_lib/os-detect.sh"
#   case "$CLAUDE_OS" in
#     macos) ... ;;
#     linux) ... ;;
#     wsl)   ... ;;
#     *)     exit 0 ;;
#   esac
#
# After sourcing, $CLAUDE_OS is one of: macos, wsl, linux, bsd, unknown.

CLAUDE_OS="unknown"
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin)
    CLAUDE_OS="macos"
    ;;
  Linux)
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null; then
      CLAUDE_OS="wsl"
    else
      CLAUDE_OS="linux"
    fi
    ;;
  FreeBSD|OpenBSD|NetBSD|DragonFly)
    CLAUDE_OS="bsd"
    ;;
esac
export CLAUDE_OS
