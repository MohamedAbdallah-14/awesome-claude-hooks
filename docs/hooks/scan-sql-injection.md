# `scan-sql-injection`

> Source: [`hooks/security/scan-sql-injection.sh`](../../hooks/security/scan-sql-injection.sh)
> Event: `PreToolUse` (matcher `Write|Edit|MultiEdit`)
> Risk level: `warn` by default, `blocking` with opt-in
> Bypass: none (per-call). `CLAUDE_SQL_BLOCK=1` upgrades warn → block; `0` (default) keeps warn-only.

## Problem

Claude is mid-feature, writing a quick admin endpoint, and concatenates a user-supplied id straight into a SQL string. It compiles, the query runs, the test passes against a happy-path fixture. A week later somebody discovers `'; DROP TABLE users; --` works and you're on the front page of HN for the wrong reason.

This hook scans every Write/Edit/MultiEdit on common backend file types and flags the string-concatenation patterns that almost always indicate an injection bug.

## What it catches

| Pattern | Example |
|---------|---------|
| Python f-string with SQL keyword | `f"SELECT * FROM users WHERE id={uid}"` |
| Python `%`-format SQL | `"SELECT ... %s" % uid` |
| String + concatenation after SQL keyword | `"SELECT * FROM x WHERE id=" + uid` |
| JS/TS template literal with SQL | `` `SELECT * FROM x WHERE id=${uid}` `` |
| PHP dot-concatenation after SQL | `"SELECT ... " . $uid` |
| `.execute()` with concatenated SQL | `db.execute("SELECT ..." + uid)` |
| `.query()` with concatenated SQL | `conn.query("SELECT ..." + uid)` |
| `cursor.execute` with f-string | `cursor.execute(f"SELECT ...")` |
| `cursor.execute` with `%` interpolation | `cursor.execute("SELECT ... %s" % uid)` |

Only runs on `.py`, `.js`, `.ts`, `.php`, `.rb`, `.java`, `.go`. Other file types pass through.

## Before

Claude wants to write:

```python
# in src/admin.py
cursor.execute(f"SELECT * FROM users WHERE id={user_id}")
```

In warn mode the write proceeds and Claude sees a stderr warning. In block mode the write is denied.

## After

Warn mode — stderr message, write proceeds:

```
[scan-sql-injection] SECURITY WARNING: potential SQL injection in src/admin.py
Matched patterns:
 - cursor.execute with format string
 - Python f-string SQL interpolation
Use parameterized queries / prepared statements instead of string concatenation.
Reference: https://owasp.org/www-community/attacks/SQL_Injection
```

Block mode — Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: SQL injection risk detected in src/admin.py. Patterns matched: cursor.execute with format string Python f-string SQL interpolation. Use parameterized queries. Set CLAUDE_SQL_BLOCK=0 to downgrade to warning."
  }
}
```

Claude rewrites the line as `cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))`.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/security/scan-sql-injection.sh"
          }
        ]
      }
    ]
  }
}
```

Or as part of the `security` profile:

```bash
bash scripts/install.sh --profile=security --global
```

## Test locally

```bash
# Warn mode
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x.py","content":"cursor.execute(f\"SELECT * FROM u WHERE id={uid}\")"}}' \
  | bash hooks/security/scan-sql-injection.sh 2>&1; echo "exit: $?"
```

Expected: exit `0`, stderr `[scan-sql-injection] SECURITY WARNING: ...`.

```bash
# Block mode
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x.py","content":"cursor.execute(f\"SELECT * FROM u WHERE id={uid}\")"}}' \
  | CLAUDE_SQL_BLOCK=1 bash hooks/security/scan-sql-injection.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

The repo's bats suite covers this hook in [`tests/security/scan-sql-injection.bats`](../../tests/security/scan-sql-injection.bats).

## Bypass

`CLAUDE_SQL_BLOCK=1` enables blocking. To skip an individual flagged write while keeping the hook installed, downgrade to warn-only by leaving `CLAUDE_SQL_BLOCK` unset (the default).

If you need the hook off entirely for a session, remove it from settings.json or run Claude without the `security` profile. There is no per-call bypass — the intent is that flagged code gets fixed, not waved through.

## Safety notes

- No network calls.
- Reads stdin only; does not open or modify the file being written.
- Heuristic regex matching. False positives happen on commented-out SQL examples or on test fixtures that deliberately demonstrate the unsafe pattern. The warn-only default is calibrated for that — pair with code review, not as a sole gate.
- Does not detect ORM-level injection (raw fragments passed to `Model.query.filter()` etc.). Pair with a static analyzer like `bandit` (Python) or `semgrep` for full coverage.
