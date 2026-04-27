# Rails Starter Pack

Drop-in `settings.json` for Ruby on Rails apps. Layers `safe-default` with database-migration guard, SQL injection scan, secret/dotenv blocks, and `main`-branch protection.

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands`.
- `devops/db-migration-guard` — blocks `db:reset` / `db:drop` and other destructive migration commands.
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

## Missing: Ruby-specific gates

There is no dedicated Ruby quality hook (no `rubocop-gate`, no `standardrb-gate`). The pack relies on `CLAUDE.md` rules for `bundle exec rubocop` discipline. **Follow-up:** add `quality/rubocop-gate.sh` (wrap `bundle exec rubocop --force-exclusion`).

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/rails/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/rails/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=team --project
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- `db-migration-guard.sh` defaults to conservative — set `CLAUDE_ALLOW_DB_DESTRUCTIVE=1` to bypass when you need to.
