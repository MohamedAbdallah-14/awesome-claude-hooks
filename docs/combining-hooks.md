# Combining Hooks

Multiple hooks can fire on the same event. Understanding how they interact lets you compose focused, single-purpose scripts into coherent workflows.

## How Multiple Hooks Work

**For PreToolUse:** hooks run in array order. If any hook exits 2 (block), Claude sees a block and the tool does not run. Subsequent hooks in the list still run unless Claude Code short-circuits on first block — so don't rely on ordering for security-critical blocks; each hook should independently validate.

**For PostToolUse and Stop:** hooks run in array order. Since they can't block the prior action, they accumulate context. All context strings are joined and presented to Claude.

**Settings.json structure with multiple hooks per event:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/security/block-secrets.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/security/bash-guard.sh"}
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/security/protect-dotenv.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/notifications/sound-complete.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/cost/session-timer.sh"}
        ]
      }
    ]
  }
}
```

Replace `$HOOKS_DIR` with the actual path: `~/.claude/hooks-lib/hooks` (or wherever you cloned the repo).

## Shared State Between Hooks

Hooks that run in the same event don't share stdin (each gets a fresh copy of the event JSON). To share state between hooks — or between PreToolUse and PostToolUse hooks for the same call — use temp files keyed by session ID.

```bash
# Hook A: PreToolUse — record start time
SESSION=$(echo "$INPUT" | jq -r '.session_id')
echo "$(date +%s%3N)" > "/tmp/claude-${SESSION}-tool-start"

# Hook B: PostToolUse — compute elapsed time
SESSION=$(echo "$INPUT" | jq -r '.session_id')
START=$(cat "/tmp/claude-${SESSION}-tool-start" 2>/dev/null || echo 0)
NOW=$(date +%s%3N)
ELAPSED=$(( NOW - START ))
echo "Tool took ${ELAPSED}ms" >&2
```

Use `/tmp/claude-{session_id}-{purpose}` as the convention. Clean up in your Stop hook if you care about temp file accumulation.

---

## Recommended Setups

### "Quiet power user"

You want to know what's happening without interruptions. These three hooks add ambient awareness with no blocking.

**Hooks:**
- `context/terminal-title.sh` — updates terminal tab title with current activity
- `notifications/sound-complete.sh` — audio cue when Claude finishes
- `cost/session-stats.sh` — brief summary at session end

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/context/terminal-title.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/notifications/sound-complete.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/cost/session-stats.sh"}
        ]
      }
    ]
  }
}
```

---

### "Safe coder"

Blocks the common foot-guns: leaked secrets, modified env files, force-pushes to main, and malformed commit messages.

**Hooks:**
- `security/block-secrets.sh` — catches API keys, tokens, private keys in any tool output
- `security/protect-dotenv.sh` — blocks writes to `.env` files
- `git/protect-main-branch.sh` — blocks destructive git operations against main/master
- `git/validate-commit-message.sh` — enforces conventional commits format

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/security/block-secrets.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/git/protect-main-branch.sh"}
        ]
      },
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/security/block-secrets.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/security/protect-dotenv.sh"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/git/validate-commit-message.sh"}
        ]
      }
    ]
  }
}
```

---

### "Quality enforcer"

All file writes go through linting and formatting. TypeScript errors and broken configs surface as Claude context so it can self-correct.

**Hooks:**
- `quality/eslint-gate.sh` — runs ESLint after JS/TS writes, injects error count as context
- `quality/prettier-gate.sh` — auto-formats on save (PostToolUse, non-blocking)
- `quality/tsc-check.sh` — runs `tsc --noEmit` after TS edits, injects error delta
- `quality/validate-json-yaml.sh` — validates JSON/YAML syntax after writes

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/quality/validate-json-yaml.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/quality/prettier-gate.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/quality/eslint-gate.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/quality/tsc-check.sh"}
        ]
      }
    ]
  }
}
```

Note: `validate-json-yaml.sh` runs first so a broken JSON file doesn't confuse the linters. Order matters here.

---

### "Full observability"

Every tool call is logged, every session is timed, and Claude always has git context. Useful when you want to audit what Claude did in a session.

**Hooks:**
- `cost/log-tool-usage.sh` — append every tool call to a daily log
- `cost/session-timer.sh` — track session start time, report at end
- `cost/daily-usage-report.sh` — generate a markdown report at session end
- `context/inject-git-context.sh` — inject current branch + dirty status before every tool call

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/cost/log-tool-usage.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/context/inject-git-context.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/cost/session-timer.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/cost/daily-usage-report.sh"}
        ]
      }
    ]
  }
}
```

---

### "Flutter developer"

Dart analysis, auto-format, test coverage, and macOS notification on completion. Works well as a project-local `.claude/settings.json` in a Flutter repo.

**Hooks:**
- `quality/dart-analyze.sh` — runs `dart analyze` after `.dart` edits, injects hint/error count
- `automation/auto-format-on-save.sh` — runs `dart format` on `.dart` files after writes
- `automation/test-coverage-check.sh` — runs `flutter test --coverage` at session end
- `notifications/macos-notify.sh` — desktop notification when Claude finishes

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/automation/auto-format-on-save.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/quality/dart-analyze.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/automation/test-coverage-check.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/notifications/macos-notify.sh"}
        ]
      }
    ]
  }
}
```

---

### "Node.js / TypeScript"

TypeScript type checking and ESLint after every edit, Prettier auto-applied, tests run at session end, Slack notification for team awareness.

**Hooks:**
- `quality/tsc-check.sh` — TypeScript errors as context after TS edits
- `quality/eslint-gate.sh` — ESLint results as context after JS/TS edits
- `quality/prettier-gate.sh` — auto-format after any edit
- `automation/auto-run-tests.sh` — runs `npm test` at session end, injects pass/fail summary
- `notifications/slack-notify.sh` — posts to Slack when Claude finishes (team setup)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/quality/prettier-gate.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/quality/eslint-gate.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/quality/tsc-check.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/automation/auto-run-tests.sh"},
          {"type": "command", "command": "bash ~/.claude/hooks/hooks/notifications/slack-notify.sh"}
        ]
      }
    ]
  }
}
```

---

## Mixing Global and Project-Local Hooks

Global hooks (`~/.claude/settings.json`) merge with project hooks (`.claude/settings.json`). Hook arrays concatenate. This lets you keep security and notification hooks global, and put project-specific quality hooks local:

**Global** (`~/.claude/settings.json`):
```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks-lib/hooks/security/block-secrets.sh"}]},
      {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks-lib/hooks/security/protect-dotenv.sh"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "bash ~/.claude/hooks-lib/hooks/notifications/sound-complete.sh"}]}
    ]
  }
}
```

**Project-local** (`.claude/settings.json` in a Flutter project):
```json
{
  "hooks": {
    "PostToolUse": [
      {"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks-lib/hooks/quality/dart-analyze.sh"}]}
    ]
  }
}
```

Result: every session in that Flutter project gets secrets blocking + env protection + sound notification (global) plus Dart analysis (local). No duplication.
