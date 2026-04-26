# `ai-migration-safety`

> Source: [`hooks/ai/ai-migration-safety.sh`](../../hooks/ai/ai-migration-safety.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `blocking` (only on `IRREVERSIBLE` verdict)
> Bypass: unset `ANTHROPIC_API_KEY`, or remove the hook

## Problem

Database migrations are not symmetric. `ALTER TABLE users ADD COLUMN email TEXT` is fine — drop the column to reverse it. `ALTER TABLE users DROP COLUMN email` is one command that erases data forever, and the diff that contains it looks identical to the safe one in a review. When Claude types `db:migrate` from a chat message, the question that matters is "can I undo this if it goes wrong" — and pattern-matching can't answer it.

This hook intercepts migration commands, asks Haiku whether the underlying migration is reversible, and blocks only when Haiku says `IRREVERSIBLE`.

## What it catches

Triggers on Bash commands matching the migration pattern:

| Command shape | Behavior |
|---------------|----------|
| `migrate`, `db:migrate` | Sent to Haiku for verdict |
| `flyway migrate` | Sent to Haiku for verdict |
| `liquibase update` | Sent to Haiku for verdict |
| `alembic upgrade` | Sent to Haiku for verdict |
| Anything else | Allowed unconditionally |

Haiku returns one of three verdicts:

| Verdict | Behavior |
|---------|----------|
| `REVERSIBLE` | Allowed |
| `UNKNOWN` | Allowed (fail-open — no false blocks) |
| `IRREVERSIBLE` | **Blocked** with the reasoning surfaced to Claude |

The fail-open default is deliberate. False positives on migrations are expensive: they break deploys and train the user to bypass the hook. False negatives are recoverable — most production setups already gate destructive migrations behind a human review.

## Before

Claude wants to run:

```
npx prisma migrate deploy
```

Without the hook, the migration runs. If the latest migration drops a column, the data is gone before anyone reads the SQL.

## After

The Bash call is intercepted. Haiku reads the command, returns `IRREVERSIBLE` plus a reason, and Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Migration blocked: Haiku assessed this as IRREVERSIBLE. The migration includes a DROP COLUMN that cannot be undone without restoring from backup."
  }
}
```

Claude can then dump the migration SQL, take a backup, or escalate to the user before re-running.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/ai/ai-migration-safety.sh"
          }
        ]
      }
    ]
  }
}
```

`ANTHROPIC_API_KEY` must be exported. Without it, every migration is allowed through (fail-open).

## Test locally

```bash
export ANTHROPIC_API_KEY=sk-ant-...
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"alembic upgrade head"}}' \
  | bash hooks/ai/ai-migration-safety.sh; echo "exit: $?"
```

Expected: exit `0`. JSON `permissionDecision: deny` if Haiku flags the migration as irreversible based on context, otherwise no output.

Non-migration command (should pass through silently):

```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | bash hooks/ai/ai-migration-safety.sh; echo "exit: $?"
```

Expected: exit `0`, no stdout.

## Bypass

There's no `CLAUDE_ALLOW_*` env var. The hook is already conservative — it only blocks when Haiku is confident the migration is irreversible, and it fails open on every other path. To disable for a session, unset `ANTHROPIC_API_KEY`. To disable permanently, remove the hook entry from `settings.json`.

If Haiku misjudges a specific command and you need to force it through once, run the underlying SQL/CLI directly outside Claude or temporarily unset the key.

## Safety notes

- **Network**: every matched migration command sends the command string (not the migration SQL itself) to `https://api.anthropic.com/v1/messages`. The hook does not read migration files from disk.
- **Cost**: roughly $0.001 per blocked-or-checked call against `claude-haiku-4-5`. Migrations are rare events, so total cost is negligible.
- **Rate limits**: 429s are swallowed by `curl -sf`. On rate-limit failure the hook exits 0 (allow). Fail-open is by design.
- **Graceful degradation**: missing key, missing tools, malformed response, non-migration command — all result in silent exit 0 (allow).
- **Soundness**: Haiku only sees the command, not the actual migration SQL. It's reasoning from filename conventions and command shape. A migration named `001_add_email_column.sql` that secretly drops a table will be misclassified. Pair with code review and backups for real safety.
- The pattern matcher uses regex. Custom migration runners with non-standard names won't trigger it. Audit your team's migration command and add the keyword to the regex if needed.
