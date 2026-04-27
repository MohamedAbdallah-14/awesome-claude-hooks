# `session-summary`

> Source: [`hooks/session/session-summary.sh`](../../hooks/session/session-summary.sh)
> Event: `Stop`
> Risk level: `modifying` (writes to `~/.claude/sessions/<date>.md`)
> Bypass: none — disable by removing it from `settings.json`.

## Problem

You finish a Claude Code turn and the session keeps going. A week later you want to remember what you did on Tuesday and you're stuck reading a transcript file. You want a one-line digest per turn, dated, in a file you can grep.

This hook gives you that. Cheap, append-only.

## What it does

Fires on every `Stop` (per-turn event). Appends a single line to `~/.claude/sessions/YYYY-MM-DD.md` with:

- `HH:MM:SS`
- current working directory
- approximate tool call count this turn

That's it. No JSON output, no decisions, no network.

## Before

A session ends. Nothing is written anywhere except Claude's own transcript.

## After

```
## 2026-04-27

- 09:14:22 | /Users/me/projects/api    | 7 tool calls
- 09:31:08 | /Users/me/projects/api    | 12 tool calls
- 11:02:55 | /Users/me/projects/site   | 4 tool calls
```

`grep -r "projects/api" ~/.claude/sessions/` later answers "what days did I touch the api repo".

## Install

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/session/session-summary.sh"
          }
        ]
      }
    ]
  }
}
```

Also bundled in the `safe-default` and `team` profiles:

```bash
bash scripts/install.sh --profile=safe-default --global
```

## Test locally

```bash
echo '{"hook_event_name":"Stop","session_id":"test","transcript_path":"/tmp/transcript","stop_hook_active":true}' \
  | bash hooks/session/session-summary.sh
ls ~/.claude/sessions/
```

Coverage: [`tests/session/session-summary.bats`](../../tests/session/session-summary.bats).

## Bypass

There's no env var. The hook is observational and cheap; if you don't want it, remove the entry from `settings.json`.

## Safety notes

- No network calls.
- No PII beyond `cwd`. Doesn't read transcript content.
- Daily file, append-only. No rotation needed at sane scale; one line per turn means a working developer accumulates ~10–20 KB/year.
- `Stop` fires per turn, not per session. For a once-per-session digest, see [`session-end-summary`](./session-end-summary.md) which uses the `SessionEnd` event.
