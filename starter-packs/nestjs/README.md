# NestJS Starter Pack

Pre-configured Claude Code hooks and project instructions for NestJS backends.

## What's included

**settings.json hooks**
- Pre-Bash: blocks secrets and `.env` mutations, dangerous shell commands, merge conflicts, and direct commits to main.
- Pre-edit/write: blocks secrets, scans for SQL injection patterns, validates JSON/YAML config files, protects the main branch.
- Post-edit: runs ESLint, TypeScript type-check, Prettier, and an audit of file write operations on every change.
- Post-Bash: injects recent git commits into context.
- On stop: desktop notification, git context summary, session stats, commit message validation.

**CLAUDE.md rules**
- Controllers orchestrate only — all logic in services.
- DTOs with class-validator for every request input; ValidationPipe with `whitelist: true` globally.
- ConfigService for all env vars; no raw `process.env` in app code.
- Constructor injection only; no manual `new` for dependencies.
- TypeORM repositories for DB access; no string-concatenated SQL.
- `kebab-case` file naming throughout.
- Ordered workflow for new features: module → service → controller → DTOs.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your project root.
2. Copy `CLAUDE.md` to your project root.
3. Replace `$HOOKS_DIR` in `settings.json` with the absolute path to the cloned `awesome-claude-hooks/hooks/` directory.
4. Verify the ORM section matches your setup (TypeORM vs Prisma) and update accordingly.
