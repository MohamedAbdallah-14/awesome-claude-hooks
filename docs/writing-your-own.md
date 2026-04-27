# Writing Your Own Hooks

Hooks are bash scripts that read JSON from stdin and optionally write JSON to stdout. That's the entire contract. This guide covers the patterns that make hooks reliable in practice.

## The Minimal Hook Template

```bash
#!/usr/bin/env bash
# my-hook.sh — one-line description of what this does

set -euo pipefail

# Read the full event JSON from stdin
INPUT=$(cat)

# Extract what you need
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""')
SESSION=$(echo "$INPUT" | jq -r '.session_id // ""')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Your logic here
# ...

# Exit 0 = parse stdout as JSON (this is how blocking decisions are reported).
# Exit 2 = print stderr to Claude as an error; stdout is ignored.
# Other non-zero = treated as allow; logged.
exit 0
```

That's 15 lines. Everything else is domain logic on top of this structure.

## Reading JSON Input

Always read stdin into a variable first, then query it multiple times. Don't pipe `cat` through `jq` repeatedly — stdin is consumed on first read.

```bash
# Correct
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Wrong — second cat returns empty
TOOL=$(cat | jq -r '.tool_name')
COMMAND=$(cat | jq -r '.tool_input.command')
```

Always provide a default with `// ""` or `// null` in your jq expressions. Claude Code may add new fields or the schema may not include a field in every context. A missing field without a default causes `jq` to output `null` as a string, which can silently break string comparisons.

```bash
# Safe
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
[ -z "$FILE" ] && exit 0   # nothing to do

# Brittle — jq exits non-zero if path doesn't exist with -e flag
FILE=$(echo "$INPUT" | jq -re '.tool_input.file_path')
```

## Exit Codes

| Code | Meaning | Effect |
|------|---------|--------|
| `0` | Success — stdout is parsed as JSON if present | JSON decision (block, approve, inject context, rewrite input) is honored |
| `2` | Error path — stdout is ignored, stderr is shown to Claude as an error | Use when you want Claude to see a plain-text reason and not a structured decision |
| Other | Error | Treated as allow in most contexts; logged |

Pick **one** signaling style per hook — never both. Claude Code does not parse JSON on exit 2; the JSON will be silently dropped.

For PreToolUse blocking, prefer the structured form: emit `hookSpecificOutput` with `permissionDecision: "deny"` and exit 0. See `docs/hook-contract.md` for the full schema.

## Writing Output: JSON vs Plain Text

Claude Code reads your hook's stdout on exit 0. The behavior depends on content:

**JSON object** — parsed and acted on:
```bash
# Block a tool call (PreToolUse — structured form)
jq -n --arg r "Reason Claude will see." '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0

# Inject context (works in all events)
echo '{"context":"Information Claude should factor into its next step."}'
exit 0
```

**Non-JSON or empty** — ignored by Claude Code, treated as allow.

The `"reason"` in a block is an instruction to Claude, not a user-facing error. Write it as a directive: "Run prettier on this file before writing it" not "Error: file not formatted."

## Logging from Hooks

Use **stderr** for debug output. Stdout is reserved for JSON responses — anything non-JSON on stdout will be silently discarded, but mixing debug text with a JSON response will break JSON parsing.

```bash
# Debug output — visible in terminal, doesn't affect Claude
echo "DEBUG: processing file $FILE" >&2

# This goes to Claude
echo '{"context":"Found 3 issues."}'
```

For persistent logs, write to a file:

```bash
LOG_DIR=~/.claude/hook-logs
mkdir -p "$LOG_DIR"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $EVENT session=$SESSION tool=$TOOL" \
  >> "$LOG_DIR/$(date +%Y-%m-%d).log"
```

## Making Hooks Idempotent

Hooks can fire multiple times in rapid succession (parallel tool calls, retries). Design them to be safe to call multiple times with the same input:

```bash
# Idempotent: appending to a log is fine
echo "..." >> "$LOG_FILE"

# Idempotent: checking a condition before acting
if ! grep -qF "$SESSION" "$STATE_FILE" 2>/dev/null; then
  echo "$SESSION" >> "$STATE_FILE"
  send_notification
fi

# Not idempotent: sending a Slack message on every call
send_slack_message "Claude is done"   # fires 3 times for 3 parallel Stop hooks
```

For notifications specifically, use a lockfile pattern:

```bash
LOCK="/tmp/claude-notify-$SESSION"
if [ ! -f "$LOCK" ]; then
  touch "$LOCK"
  send_notification
  # Clean up after 60s so future sessions can notify again
  (sleep 60 && rm -f "$LOCK") &
fi
```

## Testing Hooks Locally

Pipe synthetic event JSON directly:

```bash
# Test a Stop notification hook
echo '{"hook_event_name":"Stop","session_id":"test-abc","transcript_path":"/tmp/test.jsonl","stop_hook_active":true}' \
  | bash hooks/notifications/sound-complete.sh

# Test a PreToolUse security hook
echo '{
  "hook_event_name": "PreToolUse",
  "session_id": "test-abc",
  "transcript_path": "/tmp/test.jsonl",
  "tool_name": "Bash",
  "tool_input": {"command": "cat /etc/passwd"}
}' | bash hooks/security/bash-guard.sh

# Check exit code
echo $?   # 0 = allow, 2 = block
```

Test your jq extraction in isolation before writing the hook:

```bash
echo '{"tool_input":{"file_path":"/tmp/foo.ts"}}' | jq -r '.tool_input.file_path // ""'
```

## Environment Variables

Hooks run in a subprocess with access to the standard environment. Variables you can rely on:

| Variable | Source | Notes |
|----------|--------|-------|
| `session_id` | Input JSON | Extract with jq; not an env var |
| `PWD` | Shell | Current working directory when Claude Code launched |
| `HOME` | Shell | User home directory |
| `PATH` | Shell | Standard PATH from the user's shell profile |
| `CLAUDE_DEBUG` | User-set | Convention used in this repo; hooks check for it |

Do not rely on `CLAUDE_SESSION_ID` as an environment variable — read it from the JSON input.

## Common Patterns

### Pattern 1: Notification hook (fire and forget)

Run a side effect, exit 0. No JSON output needed.

```bash
#!/usr/bin/env bash
INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"' | cut -c1-8)

# macOS notification
osascript -e "display notification \"Done ($SESSION)\" with title \"Claude Code\"" 2>/dev/null

exit 0
```

### Pattern 2: Context injection

Read something from the environment, inject it so Claude knows.

```bash
#!/usr/bin/env bash
INPUT=$(cat)

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

CONTEXT="Current branch: $BRANCH. Uncommitted changes: $DIRTY files."
printf '{"context": "%s"}' "$CONTEXT"

exit 0
```

### Pattern 3: Gate hook (validate before allowing)

Check a condition, block if it fails.

```bash
#!/usr/bin/env bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Only validate .env files
echo "$FILE" | grep -qE '\.env' || exit 0

# Block writes to .env files (PreToolUse structured form)
jq -n --arg r "Direct writes to .env files are blocked. Use .env.example and document the change, or confirm you mean to update local env." '
{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}
'
exit 0
```

### Pattern 4: Post-processing (do something after)

Hook into PostToolUse, run a formatter or checker, inject results.

```bash
#!/usr/bin/env bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

echo "$FILE" | grep -qE '\.dart$' || exit 0
command -v dart &>/dev/null || exit 0

RESULT=$(dart format --output=none "$FILE" 2>&1)
if echo "$RESULT" | grep -q "Formatted"; then
  dart format "$FILE" &>/dev/null
  echo '{"context":"dart format applied to '"$FILE"'"}'
fi

exit 0
```

## Performance

Hooks run synchronously. A PreToolUse hook that takes 3 seconds blocks every tool call for 3 seconds. Keep hooks fast.

Targets:
- Notification hooks: < 100ms
- Linters/formatters: < 2s (acceptable for PostToolUse)
- Heavy analysis: run async

### Async pattern

For slow operations (network calls, heavy analysis), spawn a background process:

```bash
#!/usr/bin/env bash
INPUT=$(cat)

# Do the slow work in the background — don't block Claude
(
  REPORT=$(run_slow_analysis)
  echo "$REPORT" >> ~/.claude/logs/analysis.log
) &

# Detach completely so the hook exits immediately
disown

exit 0
```

Note: background processes can't inject context back into Claude (the hook has already exited). Use this pattern for logging and notifications, not for gating or context injection.

---

## Worked Example: Bash Command Logger

Log every Bash command Claude runs to a daily file.

### The hook

```bash
#!/usr/bin/env bash
# bash-command-logger.sh
# Logs every Bash command Claude executes to ~/.claude/logs/commands-YYYY-MM-DD.log

set -euo pipefail

INPUT=$(cat)

# Only handle Bash tool calls
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
[ "$TOOL" = "Bash" ] || exit 0

SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

LOG_DIR=~/.claude/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/commands-$(date +%Y-%m-%d).log"

# Append a log line — TSV format for easy parsing
printf '%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$SESSION" \
  "$COMMAND" \
  >> "$LOG_FILE"

# Silent allow — no stdout output
exit 0
```

### Installation

```bash
mkdir -p ~/.claude/hooks
cp bash-command-logger.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/bash-command-logger.sh
```

### settings.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/bash-command-logger.sh"
          }
        ]
      }
    ]
  }
}
```

### Querying the log

```bash
# See today's commands
cat ~/.claude/logs/commands-$(date +%Y-%m-%d).log

# Most frequent commands this week
cat ~/.claude/logs/commands-2025-*.log | cut -f3 | sort | uniq -c | sort -rn | head -20

# Commands for a specific session
grep "^.*\tabc-123" ~/.claude/logs/commands-$(date +%Y-%m-%d).log
```
