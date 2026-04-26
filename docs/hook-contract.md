# Hook contract

Every hook in `hooks/<category>/<name>.sh` follows this shape. The CI gate `scripts/lint-hooks.sh` enforces every rule below.

If your PR doesn't pass `bash scripts/lint-hooks.sh` locally, it won't pass CI.

## File header

The first 80 lines must contain, in this order:

1. Shebang: `#!/usr/bin/env bash`
2. SPDX line: `# SPDX-License-Identifier: CC0-1.0`
3. `# Hook name:` — kebab-case, matches the basename minus `.sh`
4. `# Event:` — one of the 28 supported Claude Code events. May include a matcher: `PreToolUse (matcher: "Write|Edit")`
5. `# Description:` — one or more lines describing what the hook does
6. `# Install` — a code block containing a JSON snippet that parses cleanly through `jq`. Required for every hook.

`set -euo pipefail` must appear before any logic.

### Supported event names

Source: <https://code.claude.com/docs/en/hooks>.

```
SessionStart           UserPromptSubmit       UserPromptExpansion
PreToolUse             PermissionRequest      PermissionDenied
PostToolUse            PostToolUseFailure     PostToolBatch
Notification
SubagentStart          SubagentStop
TaskCreated            TaskCompleted
Stop                   StopFailure            TeammateIdle
InstructionsLoaded
ConfigChange           CwdChanged             FileChanged
WorktreeCreate         WorktreeRemove
PreCompact             PostCompact
Elicitation            ElicitationResult
SessionEnd
```

The linter accepts any of these. Anything else fails CI. The installer fails loudly on unknown events — it does not silently default to `Stop`.

## I/O contract

### Stdin

Every hook reads the JSON event payload from stdin. Use `jq` for parsing.

### Stdout + exit code

Claude Code processes JSON on **exit 0 only**. On exit 2 it ignores stdout entirely and feeds **stderr** back to Claude as the error message. Pick one signaling style per hook — never both.

#### Style A — simple block (stderr + exit 2)

Best for hard, unconditional blocks where Claude doesn't need a structured reason payload.

```bash
echo "Blocked: rm -rf / detected." >&2
exit 2
```

#### Style B — structured decision (stdout JSON + exit 0)

Best for `PreToolUse` hooks that want to surface a specific permission decision plus a reason Claude can route on.

For `PreToolUse`:

```bash
jq -n --arg reason "Potential hardcoded secret detected." '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
```

For `SessionStart` / `UserPromptSubmit` (context injection):

```bash
jq -n --arg ctx "On main, 3 commits ahead." '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
exit 0
```

For `PostToolUse` (block + extra context after the tool ran):

```bash
jq -n --arg reason "TS errors after edit." --arg ctx "$TSC_OUT" '{
  decision: "block",
  reason: $reason,
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
```

Universal fields available on any JSON output:

```
continue        boolean   stop the chain after this hook
stopReason      string    surfaced to the user when continue=false
suppressOutput  boolean   hide stdout from the conversation
systemMessage   string    inject a system-message-style note
```

### Exit codes summary

| Exit | Meaning |
|------|---------|
| `0`  | Success. Stdout JSON (if present) is parsed for decisions/context. |
| `2`  | Hard block. Stdout is ignored. Stderr is fed to Claude. |
| any other non-zero | Treated as an error. Logged. Does not block. |

## Dependencies

If a hook needs a binary that may not be present (e.g. `jq`), it must:

- Check with `command -v <bin>` at the top.
- If missing, print a single-line warning to stderr and `exit 0`. Never block on a missing dependency — that would lock the user out.

## Bypass switch

Hooks that block (security, quality gates) must accept an env-var bypass. Naming convention: `CLAUDE_<PURPOSE>_<ACTION>=1`, e.g. `CLAUDE_ALLOW_SECRETS=1`, `CLAUDE_DANGEROUS_BASH_WARN_ONLY=1`. Document the variable in the header.

## Idempotency

Hooks fire many times per session. They must be safe to run repeatedly. No state in `/tmp` without a session-scoped suffix. No global locks. No log lines that depend on monotonic counters.

## Tests

Hooks under `hooks/security/`, `hooks/quality/`, and `hooks/git/` (anything that can block) must have a `.bats` file under `tests/<category>/`.

A test file must cover:

- Happy path (hook does nothing or allows the action) → `assert_allowed`
- Block path (hook returns the deny JSON on exit 0) → `assert_blocked`
- Bypass env var, if one exists.
- A non-matching tool/event (hook ignores it).

Use the helpers in `tests/test_helper.bash`:

```bash
load '../test_helper'

@test "blocks OpenAI API key" {
  payload=$(pretool_payload Write /tmp/x.py "API_KEY='sk-...'")
  run_hook "$HOOK" "$payload"
  assert_blocked
}
```
