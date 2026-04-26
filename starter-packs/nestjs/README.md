# NestJS Starter Pack

Drop-in `settings.json` for NestJS backends. Layers `safe-default` with the full JS/TS gate set (ESLint, Prettier, `tsc`), backend-relevant security (SQL injection scan, secret blocks), and team controls (main-branch protect, conflict detector, commit-message validator).

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands` — standard security stack.
- `git/protect-main-branch` — no direct pushes to `main`/`master`.
- `git/conflict-detector` — flags unresolved merge markers before commands run.

**Pre-Edit/Write**
- `security/block-secrets` — file-write path.
- `security/scan-sql-injection` — flags string-concatenated SQL in services/repositories.
- `quality/validate-json-yaml` — parse-check JSON/YAML before save.

**Post-Edit/Write**
- `quality/eslint-gate`, `quality/prettier-gate`, `quality/tsc-check` — full TS gate after each write.
- `security/audit-file-writes` — write log.

**Post-Bash**
- `context/inject-recent-commits`.

**SessionStart**
- `session/context-threshold-guard`.

**Stop**
- `notifications/desktop-notify`, `session/session-summary`, `context/inject-git-context`.
- `git/validate-commit-message` — checks last commit follows Conventional Commits before the session ends.

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/nestjs/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/nestjs/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=quality --global
# or, for main-branch + commit-message guards:
bash scripts/install.sh --profile=team --project
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- `tsc-check.sh` requires `typescript` installed in the project.
- ORM-specific advice in `CLAUDE.md` is TypeORM by default — swap for Prisma if you use it.
