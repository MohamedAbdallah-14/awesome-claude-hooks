# awesome-claude-hooks

<p align="center">
  <img src="assets/hero.png" alt="awesome-claude-hooks" width="100%">
</p>

[![Awesome](https://awesome.re/badge.svg)](https://awesome.re)
[![License: CC0](https://img.shields.io/badge/License-CC0-lightgrey.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Hooks](https://img.shields.io/badge/hooks-79-blue.svg)](#hook-catalog)
[![CI](https://github.com/MohamedAbdallah-14/awesome-claude-hooks/actions/workflows/ci.yml/badge.svg)](https://github.com/MohamedAbdallah-14/awesome-claude-hooks/actions/workflows/ci.yml)
[![shellcheck](https://img.shields.io/badge/shellcheck-clean-brightgreen.svg)](#testing)

**Production-ready Claude Code hooks**: security guards, quality gates, workflow automation, context injection, and team-safe defaults — all tested, auditable, and copy-paste installable.

79 hooks across 12 categories. shellcheck-clean. bats-tested on Ubuntu and macOS. Spec-aligned with the official Claude Code [hooks reference](https://code.claude.com/docs/en/hooks).

---

## Why this exists

Claude Code hooks let you enforce rules deterministically: block dangerous commands, prevent secret writes, run quality gates after edits, inject project context, and notify you when Claude needs attention. This repo gives you:

- working hooks, not just examples
- safe-default profiles you can install in one command
- starter packs for Next.js, Python, Go, Rails, Flutter, Rust, and more
- a hook authoring contract every contribution has to satisfy ([`docs/hook-contract.md`](docs/hook-contract.md))
- shellcheck + bats coverage on every PR
- copy-paste `settings.json` snippets in every hook header
- clear bypass + uninstall instructions

---

## Contents

- [Quick start](#quick-start)
- [Start here by intent](#start-here-by-intent)
- [Profiles](#profiles)
- [What this modifies](#what-this-modifies)
- [Hook catalog](#hook-catalog)
- [Starter packs](#starter-packs)
- [Docs](#docs)
- [Testing](#testing)
- [Contributing](#contributing)

---

## Quick start

```bash
git clone https://github.com/MohamedAbdallah-14/awesome-claude-hooks.git ~/.claude/awesome-hooks
cd ~/.claude/awesome-hooks
make install-deps                          # shellcheck, bats-core, jq, pyyaml
bash scripts/install.sh --profile=safe-default --global
```

That installs five low-risk hooks (audit logs, session summary, context warning, desktop notification) into `~/.claude/settings.json`. Claude Code picks them up on the next session.

To pick a different bundle:

```bash
bash scripts/install.sh --list-profiles    # show available profiles
bash scripts/install.sh --profile=security --global
bash scripts/install.sh --profile=team --project   # writes .claude/settings.json
```

To preview without writing anything:

```bash
bash scripts/install.sh --profile=devops --dry-run
```

---

## Start here — by intent

If you don't know what to install, pick the goal that sounds like you.

### I want safer Claude Code sessions

Block secrets, protect `.env`, stop dangerous bash, prevent system-path writes.

```bash
bash scripts/install.sh --profile=security --global
```

### I want better code quality

ESLint, Prettier, Ruff, TSC, dart analyze, go vet, JSON/YAML validation, test-coverage check.

```bash
bash scripts/install.sh --profile=quality --project
```

### I want team-ready defaults

Protect `main`, validate commit messages, audit every write, conflict detector, stash guard, daily session log.

```bash
bash scripts/install.sh --profile=team --project
```

### I want to be notified when Claude finishes

Cross-platform desktop banner, plus Slack / Telegram / Discord / Pushover / sound bridges.

```bash
bash scripts/install.sh --profile=notifications --global
```

### I deploy infrastructure

Block `terraform destroy`, `kubectl` against prod, destructive AWS calls, irreversible DB migrations, and unsafe Docker volume removal.

```bash
bash scripts/install.sh --profile=devops --global
```

### I want Haiku-powered review at edit time

Code review, OWASP scan, migration-safety check, commit-message + PR-description drafts.

```bash
export ANTHROPIC_API_KEY=sk-...
bash scripts/install.sh --profile=ai-assisted --global
```

### I'm flying solo

Auto-format, AI commit messages, session-name-from-branch, desktop notifications, project context at session start.

```bash
bash scripts/install.sh --profile=solo-dev --global
```

---

## Profiles

| Profile | Hooks | What you get |
|---------|-------|--------------|
| `safe-default` | 5 | Audit + summary + context guard + desktop notify. Reasonable starting point with zero blocking. |
| `security` | 8 | Block secrets, dangerous bash, system paths, dotenv writes. SQL injection + npm-audit scanners. |
| `quality` | 8 | Linters and gates for JS/TS/Python/Go/Dart, plus JSON/YAML validation and coverage check. |
| `team` | 6 | `main`-branch protection, commit-message validation, write audit, daily summary, conflict + stash guards. |
| `devops` | 7 | Guards for terraform / kubernetes / aws / docker / db migrations / GitHub Actions, plus an infra audit log. |
| `solo-dev` | 5 | Auto-format-on-save, AI commit messages, branch-named sessions, desktop notify, project context at start. |
| `notifications` | 10 | Desktop + macOS + Linux + Slack + Telegram + Discord + Pushover + sounds + terminal title. |
| `ai-assisted` | 5 | Haiku-powered review, OWASP scan, migration safety, commit + PR drafts. Needs `ANTHROPIC_API_KEY`. |

`bash scripts/install.sh --list-profiles` prints the resolved hook list for each.

The profile definitions live in [`hooks.registry.yaml`](hooks.registry.yaml) and are picked up automatically by the installer.

---

## What this modifies

Hooks run with your full user permissions. The installer is conservative — it touches only Claude Code's settings file.

- **May edit** `~/.claude/settings.json` (with `--global`) or `.claude/settings.json` in the cwd (with `--project`).
- **Always backs up** the existing settings file before writing (e.g. `settings.json.backup`).
- **Does not install binaries** — every hook is a shell script that lives in this repo.
- **Does not modify** your shell profile, PATH, git config, npm config, or anything outside of Claude Code's settings.
- **Each hook discloses** its dependencies, network access, and bypass env var in its header. See [`docs/compatibility.md`](docs/compatibility.md) for the full operational matrix.

For threat coverage, hook risk levels, and review guidance see [`SECURITY_MODEL.md`](SECURITY_MODEL.md).

---

## Hook catalog

The full catalog with one-line descriptions is generated from [`hooks.registry.yaml`](hooks.registry.yaml):

- **By category** → [`docs/hooks.md`](docs/hooks.md)
- **By event** → [`docs/events.md`](docs/events.md)
- **Compatibility matrix** (blocks, network access, writes files, platforms, tests) → [`docs/compatibility.md`](docs/compatibility.md)

Top-level summary:

| Category | Hooks | Examples |
|----------|------:|----------|
| [notifications/](hooks/notifications/) | 10 | desktop-notify, slack-notify, telegram-notify |
| [security/](hooks/security/) | 8 | block-secrets, protect-dotenv, block-dangerous-bash |
| [quality/](hooks/quality/) | 8 | eslint-gate, tsc-check, validate-json-yaml |
| [context/](hooks/context/) | 8 | inject-git-context, inject-typescript-errors |
| [automation/](hooks/automation/) | 7 | auto-format-on-save, auto-run-tests, auto-changelog |
| [git/](hooks/git/) | 6 | protect-main-branch, validate-commit-message, conflict-detector |
| [cost/](hooks/cost/) | 5 | budget-alert, daily-usage-report, session-timer |
| [session/](hooks/session/) | 6 | session-start-context, precompact-backup |
| [devops/](hooks/devops/) | 7 | terraform-destroy-guard, kubernetes-prod-guard |
| [ai/](hooks/ai/) | 5 | ai-code-review, ai-security-scan, ai-migration-safety |
| [prompt/](hooks/prompt/) | 5 | auto-approve-readonly, rate-limiter, banned-words-enforcer |
| [fun/](hooks/fun/) | 4 | motivational-quote, break-reminder, ascii-confetti |

Hero docs for the top 5 hooks live under [`docs/hooks/`](docs/hooks/).

---

## Starter packs

Pre-wired `settings.json` configurations for common stacks. Each pack includes a curated set of hooks from the categories above, a `settings.json` ready to drop into your project root, and a one-line install script.

| Pack | What's included |
|------|----------------|
| [nextjs/](starter-packs/nextjs/) | ESLint gate, Prettier auto-fix, TypeScript error tracking, git branch protection, Slack notify |
| [flutter/](starter-packs/flutter/) | `dart analyze` gate, `flutter test` runner, git branch protection, macOS/Linux notify |
| [python/](starter-packs/python/) | `ruff` lint gate, `black` auto-format, SQL injection scan, secret blocking, session timer |
| [nestjs/](starter-packs/nestjs/) | ESLint gate, Prettier auto-fix, TypeScript error tracking, npm audit check, git protection |
| [go/](starter-packs/go/) | `go vet` gate, `gofmt` auto-fix, secret blocking, git branch protection, session timer |
| [rails/](starter-packs/rails/) | RuboCop gate, secret blocking, DB migration safety, git branch protection, session timer |
| [rust/](starter-packs/rust/) | `cargo clippy` gate, `rustfmt` auto-fix, secret blocking, git branch protection, budget alert |
| [laravel/](starter-packs/laravel/) | PHP-CS-Fixer auto-format, secret blocking, DB migration safety, git protection, Slack notify |
| [android/](starter-packs/android/) | Kotlin lint gate, secret blocking, git branch protection, macOS/Linux notify, session timer |
| [ios/](starter-packs/ios/) | SwiftLint gate, secret blocking, git branch protection, macOS notify, session timer |
| [data-science/](starter-packs/data-science/) | `ruff` lint gate, `black` auto-format, SQL injection scan, secret blocking, budget alert |

Install a starter pack:

```bash
# Example: Next.js
cp ~/.claude/hooks/starter-packs/nextjs/settings.json .claude/settings.json
```

---

## Hero docs

Worked walkthroughs (problem, before/after, install, test, bypass, safety) for the highest-stakes hooks:

- [block-secrets](docs/hooks/block-secrets.md) — catch hardcoded API keys before they hit git
- [block-dangerous-bash](docs/hooks/block-dangerous-bash.md) — stop `rm -rf /`, fork bombs, disk wipes
- [protect-dotenv](docs/hooks/protect-dotenv.md) — refuse writes to `.env` files
- [validate-json-yaml](docs/hooks/validate-json-yaml.md) — reject broken config files at write time
- [terraform-destroy-guard](docs/hooks/terraform-destroy-guard.md) — block `terraform destroy` unless explicitly opted in

---

## Docs

- [`docs/hook-contract.md`](docs/hook-contract.md) — what every hook must include, and how to write a new one
- [`docs/hooks.md`](docs/hooks.md) — full catalog by category (generated)
- [`docs/events.md`](docs/events.md) — hooks grouped by Claude Code event (generated)
- [`docs/compatibility.md`](docs/compatibility.md) — operational matrix: blocks, network, writes, platforms (generated)
- [`SECURITY_MODEL.md`](SECURITY_MODEL.md) — threats covered + not covered, hook risk levels, review guidance
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to propose a new hook
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) — the official spec everything aligns to

---

## Testing

Every hook is shellcheck-clean. Hooks that can block (security, quality, git) have bats tests under `tests/<category>/`.

```bash
brew install shellcheck bats-core jq        # macOS
sudo apt-get install shellcheck bats jq      # Debian/Ubuntu

shellcheck -S warning hooks/**/*.sh scripts/*.sh
bash scripts/lint-hooks.sh                   # enforces docs/hook-contract.md
bats -r tests
```

CI runs all three on every push and on PRs against `main`, on Ubuntu and macOS.

---

## Contributing

Bug fixes, new hooks, and new starter packs are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the submission checklist — primarily: the script must be self-contained, work without external services by default, and include a comment block at the top describing the event, required env vars, and any optional configuration.

---

## License

CC0 — public domain. Use freely, no attribution required.
