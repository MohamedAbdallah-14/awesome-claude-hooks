---
description: List all installable hook profiles with their hook counts and members
allowed-tools: Bash
---

Run `bash scripts/install.sh --list-profiles`.

The output shows every curated profile and the hook ids it contains.

Profiles available (cross-reference with the README's Profiles section):

- `safe-default` — audit + summary + context guard + desktop notify. Reasonable starting point with zero blocking.
- `security` — block-secrets, dangerous-bash, system-paths, dotenv, sql-injection, npm-audit, audit-bash, audit-writes.
- `quality` — eslint, prettier, tsc, json/yaml validator, python-lint, dart-analyze, go-vet, test-coverage.
- `team` — main-branch protect, commit-message validate, audit, summary, conflict + stash guards.
- `devops` — terraform / kubernetes / aws / docker / db-migration / GitHub Actions guards + infra audit log.
- `solo-dev` — auto-format, AI commit messages, branch-named sessions, desktop notify, project context at start.
- `notifications` — desktop, macOS, Linux, Slack, Telegram, Discord, Pushover, sounds, terminal title.
- `ai-assisted` — AI code review, OWASP scan, migration safety, commit + PR drafts. Needs `ANTHROPIC_API_KEY`.

If the user wants to install one, run `bash scripts/install.sh --profile=<name> --global --dry-run` first to preview, then `--global` (no dry-run) once they confirm.
