# `auto-approve-readonly`

> Source: [`hooks/prompt/auto-approve-readonly.sh`](../../hooks/prompt/auto-approve-readonly.sh)
> Event: `PreToolUse` (matcher `Read|Glob|Grep|LS|WebSearch|WebFetch`)
> Risk level: `non-blocking` (approves; never denies)
> Bypass: remove the hook, or narrow the matcher

## Problem

Claude needs to read 30 files to understand the codebase. Each `Read` triggers a permission prompt. The user clicks "allow" 30 times. Half an hour in, the user starts auto-clicking without looking, which defeats the point of permission prompts entirely. The signal-to-noise ratio on confirmations collapses, and now even genuinely risky tool calls slide past unread.

This hook pre-approves the read-only tools — the ones that can't change anything on disk or in the project — so the permission system can stay sharp for the calls that actually matter (`Write`, `Edit`, `Bash`).

## What it does

Inspects the `tool_name` from the PreToolUse payload. If it's one of the documented read-only tools, returns a `permissionDecision: "allow"` JSON payload. For anything else, exits silently and lets Claude Code's normal permission flow run.

Tools auto-approved:

| Tool | Why it's read-only |
|------|-------------------|
| `Read` | Reads files from disk |
| `Glob` | File pattern matching |
| `Grep` | Content search |
| `LS` | Directory listing |
| `WebSearch` | Outbound search query |
| `WebFetch` | Outbound HTTP GET |

Anything not in that list (Write, Edit, MultiEdit, Bash, Task, etc.) gets no output, so Claude Code's existing permission rules — allowlist, project settings, user prompts — handle them as normal.

## Before

User runs Claude Code with default permissions. Claude needs to grep for a function, list a directory, and read 5 files. Every one of those triggers a confirmation. The user clicks through them, gets desensitized, and on the 7th call (`Bash: rm -rf node_modules`) clicks allow without reading because the rhythm has been established.

## After

The PreToolUse hook fires before each tool. For `Read`/`Glob`/`Grep`/`LS`/`WebSearch`/`WebFetch`, it emits:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow"
  }
}
```

Claude Code honors the decision and skips the prompt. For `Bash`, the hook outputs nothing — Claude Code's normal flow runs and the user sees the prompt with full attention.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Glob|Grep|LS|WebSearch|WebFetch|TodoRead",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/prompt/auto-approve-readonly.sh"
          }
        ]
      }
    ]
  }
}
```

The matcher and the hook's internal allowlist must agree. Adding a tool to the matcher without adding it to the script's `case` won't auto-approve it — the script will exit silently and Claude Code's normal flow will prompt.

## Test locally

Auto-approve a Read:

```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}' \
  | bash hooks/prompt/auto-approve-readonly.sh; echo "exit: $?"
```

Expected: exit `0`, stdout JSON with `permissionDecision: "allow"`.

Pass-through for a non-read tool:

```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | bash hooks/prompt/auto-approve-readonly.sh; echo "exit: $?"
```

Expected: exit `0`, no stdout (Claude Code's normal permission flow takes over).

## Bypass

There's no env-var bypass — the hook only ever approves; it never denies. To stop auto-approving:

- Remove the hook from `settings.json` to restore prompts on every read.
- Narrow the matcher (e.g. drop `WebFetch` if you don't want outbound HTTP auto-approved on a sensitive box).

If you want to *deny* a read-only tool, this is the wrong hook. Use a separate PreToolUse hook with a higher precedence that returns `permissionDecision: "deny"`.

## Safety notes

- **No network calls.** No file I/O. Reads stdin, writes stdout, exits.
- **Allowlist drift**: if Claude Code adds new read-only tools (or renames existing ones), the script's `case` must be updated. The matcher in `settings.json` is independent of the script — keep them in sync.
- **`WebFetch` is read-only-ish**: it makes an outbound HTTP request and returns the body. On a sandboxed dev box this is fine; on a machine inside a corporate network with internal-only services exposed at predictable hostnames, an attacker-controlled prompt could exfiltrate data via `WebFetch`. If your threat model includes prompt injection from untrusted documents, drop `WebFetch` from the matcher.
- **Idempotent**: the hook is stateless. Safe to fire as many times as Claude Code calls it.
- The hook always exits `0`. It never blocks Claude even on malformed input — if `tool_name` can't be parsed, it falls through to the silent default branch.
