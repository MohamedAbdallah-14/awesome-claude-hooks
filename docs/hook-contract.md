# Hook contract

Every hook in `hooks/<category>/<name>.sh` must follow this shape. The CI gate `scripts/lint-hooks.sh` enforces the structural pieces.

## File header

The first 60 lines of every hook must contain (in this order):

1. Shebang: `#!/usr/bin/env bash`
2. SPDX line: `# SPDX-License-Identifier: CC0-1.0`
3. `# Hook name:` — kebab-case, matches the basename minus `.sh`
4. `# Event:` — one of `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`, `SessionStart`, `Notification`, `UserPromptSubmit`. May include a matcher: `PreToolUse (matcher: "Write|Edit")`
5. `# Description:` — one or more lines describing what the hook does
6. `# Install` — a code block containing a JSON snippet that parses cleanly through `jq`

`set -euo pipefail` must appear before any logic.

## I/O contract

- Read the JSON event payload from stdin. Use `jq` for parsing.
- Exit codes:
  - `0` — allow / no opinion. Stdout may be informational context (for `SessionStart`/`UserPromptSubmit` hooks).
  - `2` — block. Print a JSON object on stdout: `{"decision":"block","reason":"..."}`. Claude Code surfaces the reason to the user.
  - Any other non-zero — error. Logged but does not block.
- Hooks that don't apply to the current event should `exit 0` quickly. Don't crash on unexpected payloads.

## Dependencies

If a hook needs a binary that may not be present (e.g. `jq`), it must:

- Check with `command -v <bin>` at the top.
- If missing, print a single-line warning to stderr and `exit 0`. Never block on a missing dependency — the hook would lock the user out.

## Bypass switch

User-blocking hooks (security, quality gates) must accept an env-var bypass so the user can override locally without editing the hook. Naming convention: `CLAUDE_<HOOK_PURPOSE>_<ACTION>=1`, e.g. `CLAUDE_ALLOW_SECRETS=1`, `CLAUDE_DANGEROUS_BASH_WARN_ONLY=1`. Document the variable in the header.

## Idempotency

Hooks fire many times per session. They must be safe to run repeatedly. No state in `/tmp` without a session-scoped suffix, no log lines that depend on monotonic counters, no global locks.

## Tests

Hooks under `hooks/security/`, `hooks/quality/`, and `hooks/git/` (anything that can block) must have a corresponding `.bats` file under `tests/<category>/`. Other categories are encouraged but not required.

A test file must cover, at minimum:
- The happy path (hook does nothing or allows the action).
- The block path (hook returns exit 2 with a reason).
- The bypass env var, if one exists.
- A non-matching tool/event (hook ignores it).
