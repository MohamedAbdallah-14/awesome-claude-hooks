# Laravel Starter Pack

Drop-in `settings.json` for Laravel applications. Layers `safe-default` with database-migration guard, SQL injection scan, secret/dotenv blocks, and `main`-branch protection.

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands`.
- `devops/db-migration-guard` — blocks irreversible `php artisan migrate:fresh` / `migrate:reset` / similar destructive commands.
- `git/protect-main-branch`.

**Pre-Edit/Write**
- `security/block-secrets`, `security/scan-sql-injection`, `quality/validate-json-yaml`.

**Post-Edit/Write**
- `security/audit-file-writes`.

**Post-Bash**
- `context/inject-recent-commits`.

**SessionStart**
- `session/context-threshold-guard`.

**Stop**
- `notifications/desktop-notify`, `session/session-summary`, `context/inject-git-context`, `cost/log-tool-usage`.

## Missing: PHP-specific gates

There is no dedicated PHP quality hook in this repo (no `pint-gate`, no `phpstan-gate`, no `phpcs-gate`). The pack relies on `CLAUDE.md` workflow rules and your CI to enforce style. **Follow-up:** add `quality/php-lint.sh` (wrap `vendor/bin/pint --test` or `phpcs`).

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/laravel/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/laravel/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=team --project
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- `db-migration-guard.sh` is conservative — set `CLAUDE_ALLOW_DB_DESTRUCTIVE=1` for the rare case you need it.
