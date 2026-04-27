# `session-end-summary`

> Source: [`hooks/session/session-end-summary.sh`](../../hooks/session/session-end-summary.sh)
> Event: `SessionEnd`
> Risk level: `observability`
> Bypass: `CLAUDE_SESSION_END_SUMMARY_OFF=1`

## Problem

When a Claude Code session ends, the context vanishes. You don't know how long it ran, how many tools fired, or whether the session ended cleanly or because you ran out of tokens / hit a billing wall / killed the terminal.

`Stop` fires after every Claude turn — useful but noisy. `SessionEnd` fires exactly once per session, when the session actually terminates. This hook captures one structured digest at that moment.

## What it does

Appends a markdown block to `~/.claude/sessions/YYYY-MM-DD.md`:

```markdown
### Session ended at 17:24:08 — reason: `logout`
- session id: `sess_abc123`
- cwd: `/Users/me/Work/some-repo`
- duration: 1h12m44s
- tool calls: 87 (Write 4, Edit/MultiEdit 19, Bash 41)
```

The `reason` field comes from the session's matcher and is one of:

| Value | Meaning |
|-------|---------|
| `clear` | User ran `/clear` |
| `resume` | Session was resumed (rare for SessionEnd) |
| `logout` | User logged out / quit cleanly |
| `prompt_input_exit` | User exited at the prompt |
| `bypass_permissions_disabled` | Bypass-permissions mode was disabled |
| `other` | Any other path, including crashes |

## Why both this and `session-summary`?

We ship both because they answer different questions:

| Hook | Event | Fires when | Best for |
|------|-------|------------|----------|
| [`session-summary`](./session-summary.md) | `Stop` | After every Claude turn | Per-turn instrumentation |
| `session-end-summary` | `SessionEnd` | Once, at session termination | Per-session digest |

You can run both. They write to the same daily file and don't conflict.

## Install

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/session/session-end-summary.sh"
          }
        ]
      }
    ]
  }
}
```

## Config

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAUDE_SESSIONS_DIR` | `~/.claude/sessions` | Where digests are written |
| `CLAUDE_SESSION_END_SUMMARY_OFF=1` | (unset) | Disable the hook |

## How duration is computed

The hook reads the first line of `transcript_path` (the JSONL transcript Claude maintains for the session), pulls its `timestamp` field, and subtracts from `now`. If either step fails — old transcript format, missing field, no transcript — duration is reported as `unknown` rather than guessed.

`date -d` (GNU) and `date -j -f` (BSD/macOS) are both tried, so the hook works on Linux and macOS without GNU coreutils.

## Safety notes

- Strictly observability. `SessionEnd` doesn't accept a deny decision and this hook honors that.
- Never blocks the session shutdown.
- Best-effort writes — disk errors fall through silently.
- No network calls.

## Pair with

- [`session-summary`](./session-summary.md) — per-turn digest on `Stop`.
- [`log-tool-failures`](./log-tool-failures.md) — per-failure JSONL log.
