# Cost hooks

Hook payloads don't carry API cost data, so these hooks track the next-best signals: tool call counts, session durations, bash history, and per-day usage rollups. Together they let you see how Claude is being used and flag sessions that look unusually expensive.

All five hooks write append-only logs under `~/.claude/`. Nothing here blocks tool calls.

## Hooks

- [`session-timer`](session-timer.sh) ([catalog](../../docs/hooks.md#cost)) — Records each session's duration and tool-call count to `~/.claude/sessions.log`.
- [`log-tool-usage`](log-tool-usage.sh) ([catalog](../../docs/hooks.md#cost)) — Appends a CSV row for every tool call to `~/.claude/usage.csv`. Rotates at 5 MB.
- [`log-bash-history`](log-bash-history.sh) ([catalog](../../docs/hooks.md#cost)) — Appends every bash command Claude runs, with a heuristic exit-code label, to a persistent log.
- [`budget-alert`](budget-alert.sh) ([catalog](../../docs/hooks.md#cost)) — Counts ops per session; sends a desktop notification at 50 and asks Claude to pause at 200.
- [`daily-usage-report`](daily-usage-report.sh) ([catalog](../../docs/hooks.md#cost)) — Once per day, generates a Markdown summary of sessions, tool calls, and top-edited files at `~/.claude/reports/YYYY-MM-DD.md`.

## Install just this category

```bash
bash scripts/install.sh --category=cost --global
```

No profile maps directly to this category. `daily-usage-report` and `budget-alert` rely on `session-timer` and `log-tool-usage` having run, so install all five together rather than picking one.
