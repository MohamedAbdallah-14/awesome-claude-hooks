# Fun & Productivity Hooks

Small quality-of-life additions that fire when Claude finishes. None of them are critical infrastructure — they're terminal candy and gentle nudges.

## Hooks

| Name | Description | Default On? |
|------|-------------|-------------|
| `motivational-quote.sh` | Prints a random programmer quote in an ASCII box at session end | Yes (`CLAUDE_MOTIVATIONAL=1`) |
| `break-reminder.sh` | Sends a desktop notification after 90 min of cumulative daily use | Yes (once installed) |
| `ascii-confetti.sh` | Renders a small colorful ASCII art scene (morning/afternoon/evening) | No (`CLAUDE_CONFETTI=0`) |
| `session-stats.sh` | Shows a compact stats box: duration, tool count, files edited, bash commands | Yes (`CLAUDE_SHOW_SESSION_STATS=1`) |

## What they look like

**motivational-quote.sh:**
```
  ╔════════════════════════════════════════════════════════════════╗
  ║  Premature optimization is the root of all evil.               ║
  ╟────────────────────────────────────────────────────────────────╢
  ║  — Donald Knuth                                                 ║
  ╚════════════════════════════════════════════════════════════════╝
```

**session-stats.sh:**
```
  ┌──── Session Summary ──────────────────────────┐
  │ Duration: 12 min       │ Tools used: 23        │
  │ Files edited: 4        │ Bash commands: 8      │
  └───────────────────────────────────────────────┘
```

**ascii-confetti.sh** (evening mode, color terminal):
```
  .  *  .     .  *  .
     .   *  .   .   *
  *  .     *  .  *  .
    ~ Session done. Rest well. ~
```

## Settings.json

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/fun/motivational-quote.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/fun/break-reminder.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/fun/ascii-confetti.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/fun/session-stats.sh"
          }
        ]
      }
    ]
  }
}
```

## Configuration

| Hook | Env var | Default | Effect |
|------|---------|---------|--------|
| `motivational-quote.sh` | `CLAUDE_MOTIVATIONAL` | `1` | Set to `0` to disable |
| `break-reminder.sh` | `CLAUDE_BREAK_REMINDER_INTERVAL` | `90` | Minutes before first reminder |
| `ascii-confetti.sh` | `CLAUDE_CONFETTI` | `0` | Set to `1` to enable |
| `session-stats.sh` | `CLAUDE_SHOW_SESSION_STATS` | `1` | Set to `0` to disable |

## Dependencies

- `session-stats.sh` shows richer data when `session-timer.sh` and `log-tool-usage.sh` (from `../cost/`) are also installed.
- `break-reminder.sh` reads `~/.claude/sessions.log` written by `session-timer.sh`. Without it, the reminder won't fire (no duration data to sum).
- `jq` is required by `session-stats.sh`. Others have no external dependencies beyond standard POSIX tools.

```bash
brew install jq   # macOS
apt install jq    # Debian/Ubuntu
```

All hooks skip silently when stdout is not a tty (CI, pipes, background processes).
