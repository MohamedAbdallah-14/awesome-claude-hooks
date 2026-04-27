# `log-tool-failures`

> Source: [`hooks/session/log-tool-failures.sh`](../../hooks/session/log-tool-failures.sh)
> Event: `PostToolUseFailure`
> Risk level: `observability`
> Bypass: `CLAUDE_LOG_TOOL_FAILURES_OFF=1`

## Problem

Tool calls fail. A lot. `npm test` fails because a port is in use, a `Bash` command fails because the binary isn't on PATH, an `Edit` fails because the file moved. Claude tries something else and the failure scrolls out of the transcript. A week later you can't reproduce why a session went sideways at minute 12.

This hook gives you a forensic audit trail.

## What it does

Every time a tool call fires `PostToolUseFailure`, it appends one JSONL line to `~/.claude/tool-failures/YYYY-MM-DD.jsonl`:

```json
{"ts":"2026-04-26T15:42:11Z","session_id":"sess_abc","tool_name":"Bash","duration_ms":4187,"is_interrupt":false,"error":"npm ERR! ENOENT: no such file or directory, open '/x/package.json'","tool_input":"{\"command\":\"npm test\"}"}
```

Fields:

| Field | Meaning |
|-------|---------|
| `ts` | ISO-8601 UTC timestamp of the failure |
| `session_id` | The Claude Code session id — group by this to reconstruct a session |
| `tool_name` | `Bash`, `Write`, `Edit`, etc. |
| `duration_ms` | How long the tool call ran before failing |
| `is_interrupt` | True if you Ctrl-C'd it |
| `error` | First 2 KB of stderr / error message |
| `tool_input` | First 2 KB of the tool's input JSON |

Both `error` and `tool_input` are capped at 2 KB so a runaway stack trace can't blow up the log.

## Why JSONL

Append-only, line-delimited JSON is the right format for this:

- Cheap to append from a hook (no parse-rewrite-write round trip)
- Trivial to grep / `jq` later
- Plays well with log shippers if you ever want to feed it to a real observability stack

```bash
# 10 most common failing commands today:
jq -r 'select(.tool_name=="Bash") | .tool_input' ~/.claude/tool-failures/$(date +%F).jsonl \
  | jq -r '.command' | sort | uniq -c | sort -rn | head -10

# Reconstruct one session's failure timeline:
jq -c 'select(.session_id=="sess_abc")' ~/.claude/tool-failures/2026-04-26.jsonl
```

## Install

```json
{
  "hooks": {
    "PostToolUseFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/session/log-tool-failures.sh"
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
| `CLAUDE_TOOL_FAILURES_DIR` | `~/.claude/tool-failures` | Where the daily JSONL files live |
| `CLAUDE_LOG_TOOL_FAILURES_OFF=1` | (unset) | Disable the hook entirely |

## Safety notes

- Never blocks. `PostToolUseFailure` doesn't accept a deny decision, and this hook is observability anyway.
- Best-effort writes. If the disk is full or the directory isn't writable, the hook fails silently — never breaks the session.
- 2 KB caps on `error` / `tool_input` prevent a single failure from filling your disk.
- Rotates by day. No single file grows unbounded.
- No network calls.

## Pair with

- [`suggest-fix-on-failure`](./suggest-fix-on-failure.md) — same event, but injects an actionable hint instead of just logging.
