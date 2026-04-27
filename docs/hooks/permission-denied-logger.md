# `permission-denied-logger`

> Source: [`hooks/security/permission-denied-logger.sh`](../../hooks/security/permission-denied-logger.sh)
> Event: `PermissionDenied`
> Risk level: `observability`
> Bypass: `CLAUDE_PERM_DENIED_LOG_OFF=1`

## Problem

When Claude Code denies a tool call (deny rule, auto-mode classifier, policy), the denial scrolls past in the UI and is gone. For security and compliance teams, that's the most interesting event in the entire session — somebody (Claude or, more troublingly, a prompt injection) tried to do something the policy disallowed.

This hook captures every denial to an audit log.

## What it does

On `PermissionDenied`, append one JSONL line to `~/.claude/permission-denials/YYYY-MM-DD.jsonl`:

```json
{"ts":"2026-04-26T15:42:11Z","session_id":"sess_abc","tool_name":"Bash","tool_use_id":"toolu_01ZX","denial_reason":"Destructive command matched deny rule","tool_input":"{\"command\":\"sudo rm -rf /var/log\"}"}
```

Fields:

| Field | Meaning |
|-------|---------|
| `ts` | UTC timestamp of the denial |
| `session_id` | Group denials per session |
| `tool_name` | The tool that was denied (`Bash`, `Write`, MCP tool, etc.) |
| `tool_use_id` | Anthropic's per-call id — useful when correlating with the transcript |
| `denial_reason` | First 1 KB of the reason — what rule fired |
| `tool_input` | First 2 KB of the input — what Claude was trying to do |

## Why this is observability-only

The `PermissionDenied` event supports a `retry: true` response, which can tell Claude it may retry the same call. **This hook never does that.** Audit and retry are two different jobs — pair this hook with a separate, narrowly-scoped retry hook (e.g. only retry read-only tools) if you want that behavior.

## What you can do with the log

```bash
# Top denied tools today
jq -r '.tool_name' ~/.claude/permission-denials/$(date +%F).jsonl \
  | sort | uniq -c | sort -rn

# Anything that looks like an exfiltration attempt
jq -c 'select(.tool_input | contains("curl") or contains("wget") or contains(".env"))' \
  ~/.claude/permission-denials/$(date +%F).jsonl

# Repeat denials in one session — usually means Claude is stuck looping
jq -r '.session_id' ~/.claude/permission-denials/$(date +%F).jsonl \
  | sort | uniq -c | awk '$1 > 5'
```

## Install

```json
{
  "hooks": {
    "PermissionDenied": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/security/permission-denied-logger.sh"
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
| `CLAUDE_PERM_DENIED_DIR` | `~/.claude/permission-denials` | Log directory |
| `CLAUDE_PERM_DENIED_LOG_OFF=1` | (unset) | Disable the hook |

## Safety notes

- Strictly observability. Does not set `retry`, never blocks, never escalates.
- 1 KB / 2 KB caps on text fields to bound disk usage.
- Best-effort writes — disk full / permission errors fall through silently.
- No network calls.
- Daily file rotation.

## Compliance notes

The log is suitable for SOC 2 / ISO 27001 evidence of "agent activity is monitored." For long-term retention, point `CLAUDE_PERM_DENIED_DIR` at a directory your normal log shipper already vacuums.
