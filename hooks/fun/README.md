# Fun hooks

Small quality-of-life additions that fire when Claude finishes a session: a confetti banner, a programmer quote, a session stats box, and a take-a-break nudge once you've been at it for over 90 minutes. None of these are critical infrastructure.

## Hooks

- [`ascii-confetti`](ascii-confetti.sh) ([catalog](../../docs/hooks.md#fun)) — Prints a time-of-day-themed ASCII celebration on `Stop`. Opt-in.
- [`motivational-quote`](motivational-quote.sh) ([catalog](../../docs/hooks.md#fun)) — Prints a random programmer quote in an ASCII box on `Stop`. Skips when stdout is not a tty.
- [`session-stats`](session-stats.sh) ([catalog](../../docs/hooks.md#fun)) — Prints a compact summary box (duration, tool count, files edited, bash count) on `Stop`. Reads from `session-timer` and `log-tool-usage` output.
- [`break-reminder`](break-reminder.sh) ([catalog](../../docs/hooks.md#fun)) — Sends a desktop notification once your cumulative day exceeds 90 minutes. Rate-limited to once per 30 min. Reads `~/.claude/sessions.log`.

## Install just this category

```bash
bash scripts/install.sh --category=fun --global
```

No profile maps directly to this category. `session-stats` and `break-reminder` depend on `session-timer` from the [cost](../cost/README.md) category; install both directories if you want full output.
