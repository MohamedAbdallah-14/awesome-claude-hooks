# Laravel Starter Pack

Pre-configured Claude Code hooks and project instructions for Laravel applications.

## What's included

**settings.json hooks**
- Pre-Bash: blocks hardcoded secrets, protects `.env` from mutation, blocks dangerous shell commands, guards against running migrations outside a safe context, and prevents direct commits to `main`/`master`.
- Pre-Write: audits every file write, validates JSON and YAML (including `config/*.php` array exports) before saving, and scans new code for SQL injection patterns before they land on disk.
- Post-Write: runs an AI code review on every saved file, catching Laravel anti-patterns (missing `$request->validated()`, unguarded mass assignment, sync-heavy controllers) before they reach review.
- On stop: macOS desktop notification, git context injection for the next prompt, auto-changelog update, session duration log, and a budget alert if the session cost exceeded the configured threshold.

**CLAUDE.md rules**
- `php artisan` for all Laravel operations; `php artisan test` or `vendor/bin/phpunit` for the test suite.
- `$request->validated()` required — `$request->all()` into models is banned.
- Heavy operations go in queued Jobs, not synchronous controller actions.
- Eloquent relationships used over raw joins; eager-loading required in loops.
- Every migration needs a working `down()` method.
- No hardcoded credentials anywhere in source files.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your Laravel project root.
2. Copy `CLAUDE.md` to your project root.
3. Hooks assume `~/.claude/hooks/hooks` as the base path. If you cloned the hooks repo elsewhere, replace that prefix throughout `settings.json`.
4. Set `BUDGET_ALERT_THRESHOLD` in your environment if the default budget-alert limit needs adjusting for your project.
