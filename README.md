# awesome-claude-hooks

<p align="center">
  <img src="assets/hero.png" alt="awesome-claude-hooks" width="100%">
</p>

[![Awesome](https://awesome.re/badge.svg)](https://awesome.re)
[![License: CC0](https://img.shields.io/badge/License-CC0-lightgrey.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Hooks](https://img.shields.io/badge/hooks-79-blue.svg)](#hook-categories)
[![CI](https://github.com/MohamedAbdallah-14/awesome-claude-hooks/actions/workflows/ci.yml/badge.svg)](https://github.com/MohamedAbdallah-14/awesome-claude-hooks/actions/workflows/ci.yml)
[![shellcheck](https://img.shields.io/badge/shellcheck-clean-brightgreen.svg)](#testing)

A hook library for Claude Code. Every entry is a working shell script you can drop in today. 79 hooks across 12 categories, all shellcheck-clean and bats-tested.

---

## Contents

- [What are hooks?](#what-are-claude-code-hooks)
- [Quick start](#quick-start)
- [Hook categories](#hook-categories)
- [Starter packs](#starter-packs)
- [Docs](#docs)
- [Contributing](#contributing)

---

## What are Claude Code hooks?

Claude Code hooks are shell scripts that run automatically at defined points in a session — before a tool executes, after a file write, when a session ends, and so on. They let you inject context, enforce rules, or trigger side effects without modifying your project code. Every hook here is a standalone `.sh` file: read it, `chmod +x` it, wire it up.

---

## Quick start

```bash
# 1. Clone the repo
git clone https://github.com/MohamedAbdallah-14/awesome-claude-hooks.git ~/.claude/hooks

# 2. Make hooks executable
chmod +x ~/.claude/hooks/hooks/**/*.sh

# 3. Add a hook to your Claude Code settings
```

Open (or create) `~/.claude/settings.json` and add a hook:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/hooks/notifications/macos-notify.sh"
          }
        ]
      }
    ]
  }
}
```

That's it. Claude Code picks up settings changes on the next session start.

---

## Hook categories

- [notifications/](#notifications) (10 hooks) — Cross-platform desktop, mobile, and chat alerts when Claude finishes
- [security/](#security) (8 hooks) — Block secrets, protect dotenv, SQL injection scanner, path guards
- [quality/](#quality-gates) (8 hooks) — ESLint, Prettier, Ruff, Dart analyzer, TSC, JSON/YAML validator
- [context/](#context-injection) (8 hooks) — Inject git state, recent commits, TS errors, test results
- [automation/](#automation) (7 hooks) — Auto-format, auto-test, auto-commit, auto-changelog
- [git/](#git-workflows) (6 hooks) — Protect main, conventional commits, conflict detector, PR generator
- [cost/](#cost--usage) (5 hooks) — Usage logging, session timer, budget alerts
- [session/](#session) (6 hooks) — SessionStart context, PreCompact backup, context threshold guard
- [devops/](#devops) (7 hooks) — Terraform/K8s/AWS guards, DB migration safety, audit log
- [ai/](#ai) (5 hooks) — Haiku-powered code review, security scan, commit message
- [prompt/](#prompt) (5 hooks) — Auto-approve readonly, rate limiter, banned words
- [fun/](#fun--productivity) (4 hooks) — Motivational quotes, break reminders, confetti

---

## Notifications

Run when a session ends, a tool completes, or an error fires. Useful when Claude is running a long task and you've switched windows.

**Example:** `macos-notify.sh` calls `osascript` to post a native macOS notification with the session summary as the body. Zero dependencies.

**Example:** `slack-notify.sh` POSTs to a Slack incoming webhook with the task name and exit status. Set `SLACK_WEBHOOK_URL` in your environment.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [macos-notify.sh](hooks/notifications/macos-notify.sh) | `Stop` | Desktop notification via `osascript` when Claude finishes | 🍎 macOS |
| [linux-notify.sh](hooks/notifications/linux-notify.sh) | `Stop` | Desktop notification via `notify-send` when Claude finishes | 🐧 Linux |
| [slack-notify.sh](hooks/notifications/slack-notify.sh) | `Stop` | Post task completion summary to a Slack webhook | 🌐 Both |
| [discord-notify.sh](hooks/notifications/discord-notify.sh) | `Stop` | Post task completion summary to a Discord webhook | 🌐 Both |
| [sound-complete.sh](hooks/notifications/sound-complete.sh) | `Stop` | Play a system sound on session end | 🌐 Both |
| [sound-error.sh](hooks/notifications/sound-error.sh) | `Stop` | Play an error sound when Claude exits non-zero | 🌐 Both |
| [pushover-notify.sh](hooks/notifications/pushover-notify.sh) | `Stop` | iOS/Android push notification via Pushover API | 🌐 Both |
| [telegram-notify.sh](hooks/notifications/telegram-notify.sh) | `Stop` | Send a Telegram bot message on completion | 🌐 Both |
| [terminal-title.sh](hooks/notifications/terminal-title.sh) | `PreToolUse` | Update the terminal window title with current tool and status | 🌐 Both |

---

## Security

Run as `PreToolUse` hooks — they exit non-zero to block the operation before it happens.

**Example:** `block-secrets.sh` scans the content Claude is about to write for patterns matching `sk-`, `AKIA`, `ghp_`, `xoxb-`, and similar prefixes. If a match is found, the write is blocked and Claude sees the rejection reason.

**Example:** `block-dangerous-bash.sh` rejects commands containing `rm -rf /`, `: () { :|:& };:`, `dd if=/dev/zero`, and `curl | bash` / `wget | sh` patterns before they execute.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [block-secrets.sh](hooks/security/block-secrets.sh) | `PreToolUse` | Block writes containing hardcoded API keys (OpenAI, AWS, GitHub, Slack) | 🌐 Both |
| [protect-dotenv.sh](hooks/security/protect-dotenv.sh) | `PreToolUse` | Block any write or edit to `.env` files | 🌐 Both |
| [block-system-paths.sh](hooks/security/block-system-paths.sh) | `PreToolUse` | Block writes to `/etc`, `/usr`, `/bin`, `/sbin`, `/boot` | 🌐 Both |
| [audit-file-writes.sh](hooks/security/audit-file-writes.sh) | `PostToolUse` | Append every file write to `~/.claude/audit.log` with timestamp | 🌐 Both |
| [scan-sql-injection.sh](hooks/security/scan-sql-injection.sh) | `PostToolUse` | Warn when written code contains unparameterized SQL patterns | 🌐 Both |
| [block-dangerous-bash.sh](hooks/security/block-dangerous-bash.sh) | `PreToolUse` | Block `rm -rf /`, fork bombs, disk wipes, and piped remote exec | 🌐 Both |
| [audit-bash-commands.sh](hooks/security/audit-bash-commands.sh) | `PostToolUse` | Append every bash command and its exit code to `~/.claude/bash-audit.log` | 🌐 Both |
| [check-npm-audit.sh](hooks/security/check-npm-audit.sh) | `PreToolUse` | Run `npm audit` before installing packages and surface high/critical findings | 🌐 Both |

---

## Context Injection

Run as `PreToolUse` hooks on file edits. They write to stdout; Claude Code injects that output into the context window before the tool executes.

**Example:** `inject-git-context.sh` runs `git status --short` and `git log --oneline -5` and prints them. Claude sees the current branch state before touching any file.

**Example:** `inject-typescript-errors.sh` runs `tsc --noEmit 2>&1 | tail -20` and reports the current error count. Claude knows how many errors exist before an edit and can verify the count went down after.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [inject-git-context.sh](hooks/context/inject-git-context.sh) | `PreToolUse` | Inject `git status` and recent log into context before file edits | 🌐 Both |
| [inject-recent-commits.sh](hooks/context/inject-recent-commits.sh) | `PreToolUse` | Inject file-specific `git log` before editing that file | 🌐 Both |
| [inject-test-results.sh](hooks/context/inject-test-results.sh) | `PreToolUse` | Show the last test run results before editing source files | 🌐 Both |
| [inject-typescript-errors.sh](hooks/context/inject-typescript-errors.sh) | `PreToolUse` | Show current TypeScript error count before `.ts`/`.tsx` edits | 🌐 Both |
| [inject-env-summary.sh](hooks/context/inject-env-summary.sh) | `PreToolUse` | Inject Node, Python, Go, Flutter runtime versions and `$PATH` summary | 🌐 Both |
| [inject-package-info.sh](hooks/context/inject-package-info.sh) | `PreToolUse` | Inject `package.json` or `pubspec.yaml` summary when editing dependency files | 🌐 Both |
| [inject-docker-status.sh](hooks/context/inject-docker-status.sh) | `PreToolUse` | Show running containers when Claude issues Docker commands | 🌐 Both |
| [inject-file-history.sh](hooks/context/inject-file-history.sh) | `PreToolUse` | Inject a `git blame` summary (authors, last-changed dates) before editing | 🌐 Both |

---

## Quality Gates

Run as `PostToolUse` hooks after file writes. They exit non-zero on failure, surfacing errors directly in the Claude Code output so the next step can fix them.

**Example:** `tsc-check.sh` compares the TypeScript error count before and after an edit. If it went up, the hook fails and prints the new errors. Claude sees this as feedback and self-corrects.

**Example:** `validate-json-yaml.sh` runs `python3 -m json.tool` or `python3 -c "import yaml"` on the written file and blocks the session step if the file is malformed — before the bad file lands in a commit.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [eslint-gate.sh](hooks/quality/eslint-gate.sh) | `PostToolUse` | Run ESLint after `.js`/`.ts` writes; fail on errors | 🌐 Both |
| [prettier-gate.sh](hooks/quality/prettier-gate.sh) | `PostToolUse` | Check Prettier formatting after writes; optionally auto-fix | 🌐 Both |
| [python-lint.sh](hooks/quality/python-lint.sh) | `PostToolUse` | Run `ruff` (falls back to `flake8`) after `.py` writes | 🌐 Both |
| [dart-analyze.sh](hooks/quality/dart-analyze.sh) | `PostToolUse` | Run `dart analyze` after `.dart` writes | 🌐 Both |
| [tsc-check.sh](hooks/quality/tsc-check.sh) | `PostToolUse` | Track TypeScript error delta after every `.ts`/`.tsx` edit | 🌐 Both |
| [validate-json-yaml.sh](hooks/quality/validate-json-yaml.sh) | `PostToolUse` | Block invalid JSON or YAML before it persists to disk | 🌐 Both |
| [go-vet.sh](hooks/quality/go-vet.sh) | `PostToolUse` | Run `go vet` and `gofmt -l` after `.go` writes | 🌐 Both |
| [test-coverage-check.sh](hooks/quality/test-coverage-check.sh) | `PostToolUse` | Run tests when test files change and report coverage delta | 🌐 Both |

---

## Automation

Run as `PostToolUse` or `Stop` hooks. They do work so you don't have to.

**Example:** `auto-prettier.sh` runs `prettier --write` on the file Claude just wrote. The diff Claude sees on the next read already has correct formatting — no separate format step needed.

**Example:** `auto-changelog.sh` appends a timestamped entry to `CHANGELOG.md` on session end, using the last commit message as the entry text.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [auto-prettier.sh](hooks/automation/auto-prettier.sh) | `PostToolUse` | Auto-format JS/TS/CSS files with Prettier immediately after write | 🌐 Both |
| [auto-run-tests.sh](hooks/automation/auto-run-tests.sh) | `PostToolUse` | Run the test suite for the module Claude just edited | 🌐 Both |
| [auto-git-commit.sh](hooks/automation/auto-git-commit.sh) | `Stop` | Auto-commit all changes on session end (opt-in via env flag) | 🌐 Both |
| [auto-push.sh](hooks/automation/auto-push.sh) | `Stop` | Auto-push to remote after auto-commit (opt-in, requires `auto-git-commit.sh`) | 🌐 Both |
| [auto-changelog.sh](hooks/automation/auto-changelog.sh) | `Stop` | Append a changelog entry on session end | 🌐 Both |
| [auto-format-on-save.sh](hooks/automation/auto-format-on-save.sh) | `PostToolUse` | Detect language and run the appropriate formatter (Prettier/Black/gofmt/dartfmt) | 🌐 Both |
| [auto-update-readme.sh](hooks/automation/auto-update-readme.sh) | `PostToolUse` | Sync version string in `README.md` when `package.json` version changes | 🌐 Both |

---

## Git Workflows

Run as `PreToolUse` hooks on bash commands. They inspect the command string and block or warn before git destructive operations execute.

**Example:** `protect-main-branch.sh` intercepts any `git push --force`, `git reset --hard`, or `git checkout .` while on `main` or `master` and exits non-zero with a clear message. Claude sees the block and uses a safer alternative.

**Example:** `validate-commit-message.sh` checks the commit message Claude is about to use against the Conventional Commits spec (`feat:`, `fix:`, `chore:`, etc.) and rejects commits that don't match.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [protect-main-branch.sh](hooks/git/protect-main-branch.sh) | `PreToolUse` | Block force pushes and hard resets on `main`/`master` | 🌐 Both |
| [validate-commit-message.sh](hooks/git/validate-commit-message.sh) | `PreToolUse` | Enforce Conventional Commits format before `git commit` | 🌐 Both |
| [auto-create-branch.sh](hooks/git/auto-create-branch.sh) | `PreToolUse` | Suggest branch creation when committing on `main` with changes | 🌐 Both |
| [stash-guard.sh](hooks/git/stash-guard.sh) | `PreToolUse` | Warn about uncommitted changes before checkout or rebase | 🌐 Both |
| [conflict-detector.sh](hooks/git/conflict-detector.sh) | `PreToolUse` | Warn when Claude is editing a file that contains merge conflict markers | 🌐 Both |
| [pr-description-gen.sh](hooks/git/pr-description-gen.sh) | `PreToolUse` | Inject recent commit history as context before `gh pr create` | 🌐 Both |

---

## Cost & Usage

Run as `PostToolUse` or `Stop` hooks. They write to local files — no external services.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [log-tool-usage.sh](hooks/cost/log-tool-usage.sh) | `PostToolUse` | Append every tool call to `~/.claude/tool-usage.csv` (tool, file, timestamp) | 🌐 Both |
| [session-timer.sh](hooks/cost/session-timer.sh) | `Stop` | Log session duration and total tool call count to `~/.claude/sessions.log` | 🌐 Both |
| [daily-usage-report.sh](hooks/cost/daily-usage-report.sh) | `Stop` | Generate a daily summary from `tool-usage.csv` grouped by tool type | 🌐 Both |
| [budget-alert.sh](hooks/cost/budget-alert.sh) | `PostToolUse` | Print a warning when the session crosses 100 / 500 / 1000 tool calls | 🌐 Both |
| [log-bash-history.sh](hooks/cost/log-bash-history.sh) | `PostToolUse` | Log every bash command with exit code and duration to `~/.claude/bash-history.log` | 🌐 Both |

---

## Fun & Productivity

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [motivational-quote.sh](hooks/fun/motivational-quote.sh) | `Stop` | Print a random dev quote from a bundled list on session end | 🌐 Both |
| [break-reminder.sh](hooks/fun/break-reminder.sh) | `Stop` | Remind you to take a break if the session has run longer than 90 minutes | 🌐 Both |
| [ascii-confetti.sh](hooks/fun/ascii-confetti.sh) | `Stop` | ASCII art celebration when Claude exits with status 0 | 🌐 Both |
| [session-stats.sh](hooks/fun/session-stats.sh) | `Stop` | Print session duration, total tool calls, and files changed on exit | 🌐 Both |

---

## Session

Run on `SessionStart`, `PreCompact`, and `Stop` hooks. They manage context health and persist state across compactions.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [session-start-context.sh](hooks/session/session-start-context.sh) | `SessionStart` | Inject project summary, recent git log, and open TODOs at session start | 🌐 Both |
| [precompact-backup.sh](hooks/session/precompact-backup.sh) | `PreCompact` | Snapshot the current transcript before compaction | 🌐 Both |
| [context-threshold-guard.sh](hooks/session/context-threshold-guard.sh) | `UserPromptSubmit` | Warn when context is getting long and suggest `/compact` | 🌐 Both |
| [session-summary.sh](hooks/session/session-summary.sh) | `Stop` | Append a one-line summary of the session to a daily markdown log | 🌐 Both |
| [session-name-from-branch.sh](hooks/session/session-name-from-branch.sh) | `SessionStart` | Name the session after the current git branch | 🌐 Both |
| [env-file-injector.sh](hooks/session/env-file-injector.sh) | `SessionStart` | Load `.claude.env` from the repo root and inject keys as session context | 🌐 Both |

---

## DevOps

Run as `PreToolUse` hooks on bash commands. They block or warn before infrastructure-modifying operations execute.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [terraform-destroy-guard.sh](hooks/devops/terraform-destroy-guard.sh) | `PreToolUse` | Block `terraform destroy` unless `CLAUDE_ALLOW_DESTROY=1` is set | 🌐 Both |
| [kubernetes-prod-guard.sh](hooks/devops/kubernetes-prod-guard.sh) | `PreToolUse` | Block `kubectl` commands targeting production clusters or namespaces | 🌐 Both |
| [aws-prod-guard.sh](hooks/devops/aws-prod-guard.sh) | `PreToolUse` | Block destructive `aws` CLI commands targeting production profiles | 🌐 Both |
| [db-migration-guard.sh](hooks/devops/db-migration-guard.sh) | `PreToolUse` | Block irreversible DB operations (`DROP`, `TRUNCATE`, unsafe `DELETE`, rollbacks) | 🌐 Both |
| [docker-prod-guard.sh](hooks/devops/docker-prod-guard.sh) | `PreToolUse` | Block `docker rm/stop/kill/volume rm` on prod-named containers and volumes | 🌐 Both |
| [github-actions-validator.sh](hooks/devops/github-actions-validator.sh) | `PreToolUse` | Validate YAML syntax of workflow files before they are written | 🌐 Both |
| [infra-audit-log.sh](hooks/devops/infra-audit-log.sh) | `PostToolUse` | Log infra commands (`terraform`, `kubectl`, `aws`, `gcloud`, `helm`, `docker`) to `~/.claude/infra-audit.log` | 🌐 Both |

---

## AI

Run as `PostToolUse` hooks. They shell out to the Claude API (Haiku by default) for fast, cheap automated review.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [ai-code-review.sh](hooks/ai/ai-code-review.sh) | `PostToolUse` | Haiku-powered post-write review — flags bugs, anti-patterns, and obvious issues | 🌐 Both |
| [ai-security-scan.sh](hooks/ai/ai-security-scan.sh) | `PostToolUse` | Haiku-powered security scan of written code looking for common vulnerabilities | 🌐 Both |
| [ai-commit-message.sh](hooks/ai/ai-commit-message.sh) | `Stop` | Generate a conventional commit message from the session diff using Haiku | 🌐 Both |
| [ai-pr-description.sh](hooks/ai/ai-pr-description.sh) | `Stop` | Draft a PR description from the session's git diff using Haiku | 🌐 Both |
| [ai-migration-safety.sh](hooks/ai/ai-migration-safety.sh) | `PreToolUse` | Haiku-powered migration safety review before destructive DB ops run | 🌐 Both |

---

## Prompt

Run as `PreToolUse` hooks on permission and tool events. They shape what Claude is allowed to do automatically.

| Hook | Event | Description | Platform |
|------|-------|-------------|----------|
| [auto-approve-readonly.sh](hooks/prompt/auto-approve-readonly.sh) | `PreToolUse` | Auto-approve Read, Glob, Grep, and LS tool calls — eliminates read-only permission prompts | 🌐 Both |
| [rate-limiter.sh](hooks/prompt/rate-limiter.sh) | `PreToolUse` | Throttle tool calls per minute to avoid runaway loops | 🌐 Both |
| [banned-words-enforcer.sh](hooks/prompt/banned-words-enforcer.sh) | `PreToolUse` | Block writes containing a configurable list of banned strings | 🌐 Both |
| [no-ask-human-blocker.sh](hooks/prompt/no-ask-human-blocker.sh) | `UserPromptSubmit` | Detect "ask the user" / "wait for confirmation" in prompts and reroute Claude to act autonomously | 🌐 Both |
| [session-context-injector.sh](hooks/prompt/session-context-injector.sh) | `UserPromptSubmit` | Inject session-wide context tags into every user prompt | 🌐 Both |

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

## How to test a hook

All hooks read a JSON payload from stdin. Pipe a synthetic event to test locally:

```bash
# Test a Stop hook (notification, session-stats, etc.)
echo '{"hook_event_name":"Stop","session_id":"test","transcript_path":"/tmp/test","stop_hook_active":true}' \
  | bash ~/.claude/hooks/hooks/notifications/macos-notify.sh

# Test a PreToolUse security hook — check exit code to see if it blocks
echo '{"hook_event_name":"PreToolUse","session_id":"test","transcript_path":"/tmp/test","tool_name":"Write","tool_input":{"file_path":"/tmp/test.py","content":"password = \"hunter2\""}}' \
  | bash ~/.claude/hooks/hooks/security/block-secrets.sh; echo "Exit: $?"

# Test a PostToolUse quality hook
echo '{"hook_event_name":"PostToolUse","session_id":"test","transcript_path":"/tmp/test","tool_name":"Write","tool_input":{"file_path":"src/index.ts","content":"const x = 1"},"tool_response":{}}' \
  | bash ~/.claude/hooks/hooks/quality/eslint-gate.sh
```

Exit 0 = allowed. Exit 2 = blocked (PreToolUse only). Any stdout JSON with `"decision":"block"` is what Claude Code sees as the rejection reason.

---

## Notable hooks

Five standout hooks worth knowing about:

- **[ai/ai-code-review.sh](hooks/ai/ai-code-review.sh)** — Haiku-powered post-write review. Flags bugs before you move on, zero manual steps.
- **[devops/terraform-destroy-guard.sh](hooks/devops/terraform-destroy-guard.sh)** — Blocks `terraform destroy` unless you explicitly set `ALLOW_DESTROY=1`. One-line opt-in, hard stop by default.
- **[session/context-threshold-guard.sh](hooks/session/context-threshold-guard.sh)** — Warns when context is getting long and suggests `/compact`. Keeps sessions from silently degrading.
- **[security/block-secrets.sh](hooks/security/block-secrets.sh)** — Catches 7 credential patterns (OpenAI, AWS, GitHub, Slack, and more) before they hit git.
- **[prompt/auto-approve-readonly.sh](hooks/prompt/auto-approve-readonly.sh)** — Eliminates permission prompts for Read, Glob, Grep, and LS. Safe to enable globally.

---

## Docs

- [How to test a hook](#how-to-test-a-hook)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/hook-contract.md](docs/hook-contract.md) — what every hook must include
- [Claude Code hooks reference](https://docs.anthropic.com/claude-code/hooks)

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
