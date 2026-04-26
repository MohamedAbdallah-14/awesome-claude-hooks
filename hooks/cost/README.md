# Cost & Usage Tracking Hooks

Claude Code doesn't expose API costs in hook payloads. These hooks track the next-best thing: operation counts, session durations, tool call patterns, and bash command history. Over time they build a detailed picture of how you use Claude — where you spend sessions, which tools dominate, how long things take.

## Why it matters

- **Spot inefficiencies.** If one session consistently runs 200+ operations, that's a workflow worth examining.
- **Audit trail.** Know exactly which files Claude touched and which commands it ran, even days later.
- **Budget awareness.** No hard cost number, but operation count is a reliable proxy for usage volume.
- **Reproduce sessions.** The bash history log is invaluable for debugging what Claude ran when something broke.

## Hooks

| Name | Event | Description | Output |
|------|-------|-------------|--------|
| `log-tool-usage.sh` | PostToolUse | Logs every tool call (tool name + file/command context) | `~/.claude/usage.csv` |
| `session-timer.sh` | PreToolUse + Stop | Records session start, counts tool calls, logs duration on Stop | `~/.claude/sessions.log` |
| `daily-usage-report.sh` | Stop | Generates a daily Markdown summary once per day | `~/.claude/reports/YYYY-MM-DD.md` |
| `budget-alert.sh` | PostToolUse | Sends desktop notifications at 50/100/200 ops; emits context block at 200 | `/tmp/claude-ops-{id}.count` |
| `log-bash-history.sh` | PostToolUse (Bash) | Appends every bash command with inferred exit code | `~/.claude/bash-history.log` |

> **Note:** There is no direct access to Anthropic API costs from hook payloads. All cost-related hooks track *proxy metrics* (operations, duration, calls) rather than dollars.

## Settings.json

Add to `~/.claude/settings.json` (or project `.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/cost/session-timer.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/cost/log-tool-usage.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/cost/budget-alert.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/cost/log-bash-history.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/cost/session-timer.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/cost/daily-usage-report.sh"
          }
        ]
      }
    ]
  }
}
```

## Configuration

Each hook reads env vars for overrides:

| Hook | Env var | Default |
|------|---------|---------|
| `log-tool-usage.sh` | `CLAUDE_USAGE_LOG` | `~/.claude/usage.csv` |
| `session-timer.sh` | `CLAUDE_SESSION_LOG` | `~/.claude/sessions.log` |
| `daily-usage-report.sh` | `CLAUDE_DAILY_REPORT_PATH` | `~/.claude/reports/` |
| `budget-alert.sh` | `CLAUDE_BUDGET_SOFT_LIMIT` | `50` |
| `budget-alert.sh` | `CLAUDE_BUDGET_HARD_LIMIT` | `200` |
| `log-bash-history.sh` | `CLAUDE_BASH_HISTORY_LOG` | `~/.claude/bash-history.log` |

## Hook interdependencies

- `daily-usage-report.sh` reads output from both `log-tool-usage.sh` and `session-timer.sh`. Install all three for a complete report.
- `session-stats.sh` (in `../fun/`) also reads `session-timer.sh` tmp files. Running them together gives you in-terminal stats plus a persistent log.

## Requirements

All hooks require `jq`. Install it:

```bash
brew install jq        # macOS
apt install jq         # Debian/Ubuntu
```
