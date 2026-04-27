# `suggest-fix-on-failure`

> Source: [`hooks/quality/suggest-fix-on-failure.sh`](../../hooks/quality/suggest-fix-on-failure.sh)
> Event: `PostToolUseFailure` (matcher `Bash`)
> Risk level: `advisory`
> Bypass: `CLAUDE_SUGGEST_FIX_OFF=1`

## Problem

A `Bash` tool call fails. Claude reads the error, often guesses something plausible-looking, and burns three more turns going in circles. The fix was usually obvious to a human: `npm install` first, activate the venv, or `lsof` the port.

This hook closes that loop deterministically. No LLM call, no network — pure pattern matching against the command + stderr.

## What it does

When a `Bash` failure fires `PostToolUseFailure`, the hook scans the command and error for a known-bad pattern. If it finds one, it emits a Style B JSON response with `additionalContext` that Claude sees on the next turn:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": "Hint from suggest-fix-on-failure: Port 3000 is already in use. Find the offender: 'lsof -i :3000' (macOS/Linux) or 'netstat -ano | findstr 3000' (Windows), then kill it or pick a different port."
  }
}
```

Claude reads that on its next turn and acts on it.

## What it catches

| Pattern family | Example trigger | Hint surfaced |
|----------------|-----------------|---------------|
| Node missing module | `Error [ERR_MODULE_NOT_FOUND]` | Suggests `npm install` (or pnpm/yarn) |
| Node lockfile drift | `ERR_PNPM_OUTDATED_LOCKFILE` | Suggests regenerating |
| Node peer-dep conflict | `ERESOLVE`, `peer dependency` | Suggests `--legacy-peer-deps` |
| Python missing module | `ModuleNotFoundError: No module named 'X'` | Names X, suggests venv/install |
| Python PEP 668 | `externally-managed-environment` | Suggests venv |
| Cargo missing manifest | `could not find Cargo.toml` | Suggests cwd / `--manifest-path` |
| Rust unresolved crate | `unresolved import` | Suggests `cargo add` |
| Go missing module | `cannot find main module` | Suggests `go mod init` |
| Go stale checksum | `missing go.sum entry` | Suggests `go mod tidy` |
| Ruby missing gem | `Bundler::GemNotFound` | Suggests `bundle install` |
| Port in use | `EADDRINUSE`, `address already in use` | Surfaces the port number, suggests `lsof` |
| Command not found | `: command not found` | Names the missing binary |
| Permission denied | `EACCES`, `permission denied` | Warns against `sudo`, suggests fixing ownership |
| Connection refused | `ECONNREFUSED` | Suggests checking dev DB / docker |
| Tests failing | `--- FAIL:`, `Tests: N failed` | Suggests isolating one failing test |
| Git not a repo | `fatal: not a git repository` | Suggests `cd` / `git init` |
| Merge conflict | `CONFLICT (content)` | Suggests resolve + continue |
| Out of disk | `ENOSPC` | Suggests `df -h` |

If nothing matches, the hook stays quiet. It deliberately does not guess.

## Install

```json
{
  "hooks": {
    "PostToolUseFailure": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/quality/suggest-fix-on-failure.sh"
          }
        ]
      }
    ]
  }
}
```

## Why this isn't an LLM call

Three reasons:

1. **Latency**. A network round-trip on every Bash failure adds up fast.
2. **Cost**. You're already paying for Claude — adding another LLM in the hook is wasteful for problems with deterministic answers.
3. **Predictability**. A regex either matches or it doesn't. Claude downstream of an LLM hint can second-guess hallucinations; it tends to trust deterministic ones.

If you want LLM-grade suggestions, run a separate hook that calls a smaller model. This one stays in the boring, fast, free lane.

## Bypass

Set `CLAUDE_SUGGEST_FIX_OFF=1` to silence the hook.

## Safety notes

- Pure read. No writes, no network, no `eval`.
- Caps the haystack at 8 KB to bound regex cost.
- Never blocks. `PostToolUseFailure` is non-blocking by spec.
- First match wins. Most-specific patterns are listed first.

## Pair with

- [`log-tool-failures`](./log-tool-failures.md) — record what failed; this one tries to help fix it.
