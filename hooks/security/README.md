# Security hooks

Hooks that enforce security guardrails on Claude's tool calls: scan content for hardcoded secrets, refuse writes to `.env` and system paths, block catastrophic shell commands, intercept SQL-injection patterns, remind on `npm install`, and append an audit log of every bash command and file write. They run inline with the tool invocation, no background process.

Test these on a dev session before installing globally. Misconfigured blockers will stop Claude from doing useful work. See [`SECURITY_MODEL.md`](../../SECURITY_MODEL.md) for the threat model.

## Hooks

- [`block-secrets`](block-secrets.sh) ([catalog](../../docs/hooks.md#security)) — Blocks writes that contain OpenAI/AWS/GitHub/Slack tokens or `password=`/`secret=`/`api_key=` assignments.
- [`protect-dotenv`](protect-dotenv.sh) ([catalog](../../docs/hooks.md#security)) — Blocks writes to `.env` and `.env.*` files.
- [`block-dangerous-bash`](block-dangerous-bash.sh) ([catalog](../../docs/hooks.md#security)) — Blocks `rm -rf /`, fork bombs, `dd` to disk devices, `mkfs.*`, and `curl|bash` patterns.
- [`block-system-paths`](block-system-paths.sh) ([catalog](../../docs/hooks.md#security)) — Blocks writes under `/etc`, `/usr`, `/bin`, `/sbin`, `/boot`, `/sys`, `/proc`, `/lib`, and bash redirects into them.
- [`scan-sql-injection`](scan-sql-injection.sh) ([catalog](../../docs/hooks.md#security)) — Warns on string-concatenated SQL in `.py`/`.js`/`.ts`/`.php`/`.rb`/`.java`/`.go`. Set `CLAUDE_SQL_BLOCK=1` to block.
- [`check-npm-audit`](check-npm-audit.sh) ([catalog](../../docs/hooks.md#security)) — Reminds on `npm install`/`yarn add`/`pnpm add`. Set `CLAUDE_NPM_AUDIT_BLOCK=1` to run `npm audit` and block on critical findings.
- [`audit-bash-commands`](audit-bash-commands.sh) ([catalog](../../docs/hooks.md#security)) — Logs every bash command (with heuristic exit code) to `~/.claude/bash-audit.log`. Rotates at 10 MB.
- [`audit-file-writes`](audit-file-writes.sh) ([catalog](../../docs/hooks.md#security)) — Logs every file write (path + byte count) to `~/.claude/audit.log`. Rotates at 10 MB.

## Install just this category

The `security` profile pulls the most useful hooks here, plus the two audit hooks:

```bash
bash scripts/install.sh --profile=security --global
```

Or install everything in this directory:

```bash
bash scripts/install.sh --category=security --global
```

For shared team settings, use `--project` so the rules ship with the repo.
