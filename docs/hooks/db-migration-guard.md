# `db-migration-guard`

> Source: [`hooks/devops/db-migration-guard.sh`](../../hooks/devops/db-migration-guard.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `blocking`
> Bypass: none — this hook does not provide a session-level override

## Problem

Claude is "fixing" a flaky integration test and decides the cleanest reset is `psql -c "TRUNCATE users"`. Or it's helping with a migration and runs `npx knex migrate:rollback` against a prod connection string that's still in `.env`. Or it sees a stuck table and reaches for `DROP TABLE jobs`. There is no undo for any of these — the row data is gone, the schema is gone, the migration history is gone.

This hook blocks the irreversible DB operations regardless of which CLI is wrapping them.

## What it catches

Looks at `psql`, `mysql`, `sqlite3`, `pg_dump`, `mongosh`, `mongo` invocations and any inline SQL. Also matches migration-rollback flags from common ORMs.

| Pattern | Why |
|---------|-----|
| `DROP TABLE <name>` | Schema gone |
| `DROP DATABASE <name>` | Database gone |
| `DROP SCHEMA <name>` | Schema gone |
| `TRUNCATE [TABLE] <name>` | All rows gone, no transaction log |
| `DELETE FROM <name>` with no `WHERE` | Full table delete |
| `--down`, `rollback`, `migrate:down`, `db:rollback` | ORM migration rollback |

The SQL match is case-insensitive (the command is uppercased before matching). The DELETE rule fires only if no `WHERE` keyword appears anywhere in the command.

## Before

Claude wants to run:

```
psql -c "DELETE FROM events;"
```

Or:

```
npx knex migrate:rollback
```

Without the hook, the data or the migration is gone.

## After

The Bash call is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Irreversible DB operation detected: DELETE FROM without WHERE clause (full table delete). This operation cannot be undone. Aborting."
  }
}
```

Or for a rollback:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Irreversible DB operation detected: migration rollback via 'migrate:down'. This operation cannot be undone. Aborting."
  }
}
```

Claude rewrites the DELETE with a `WHERE` clause, or runs the rollback in a sandbox DB by hand.

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
            "command": "/abs/path/to/hooks/devops/db-migration-guard.sh"
          }
        ]
      }
    ]
  }
}
```

Or as part of the `devops` profile:

```bash
bash scripts/install.sh --profile=devops --global
```

## Test locally

```bash
# Blocked: DROP TABLE
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"psql -c \"DROP TABLE users;\""}}' \
  | bash hooks/devops/db-migration-guard.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Blocked: unscoped DELETE
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM events;\""}}' \
  | bash hooks/devops/db-migration-guard.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Allowed: scoped DELETE
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM events WHERE id=1;\""}}' \
  | bash hooks/devops/db-migration-guard.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

```bash
# Blocked: migration rollback
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npx knex migrate:rollback"}}' \
  | bash hooks/devops/db-migration-guard.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

The repo's bats suite covers this hook in [`tests/devops/db-migration-guard.bats`](../../tests/devops/db-migration-guard.bats).

## Bypass

There is no env-var bypass. The blocked operations are irreversible and the cost of a false negative is "data loss in production"; the cost of a false positive is "type the command in your own terminal". That tradeoff is intentional.

If you genuinely need to drop a table or roll back a migration, run it directly in your DB client outside of Claude. If you need this hook off entirely (for a sandbox, or a migration-heavy session), remove it from settings.json or run Claude without the `devops` profile.

## Safety notes

- No network calls. Does not connect to any database.
- Stateless — reads stdin, makes a decision, exits.
- The DELETE-without-WHERE check is a substring scan: a `WHERE` anywhere in the command counts. A multi-statement query with one `DELETE FROM x;` and a separate `WHERE`-clause query elsewhere will pass through. Run multi-statement migrations through a script file, not as a single shell argument, if you want each statement audited individually.
- The SQL match works on inline `-c "..."` / `-e "..."` arguments. SQL piped from a file (`psql < migration.sql`) is not inspected — the hook does not read files. Pair with code review on `.sql` files.
- Pair with [`infra-audit-log`](../../hooks/devops/infra-audit-log.sh) (PostToolUse) to keep an audit trail of every DB command Claude runs.
