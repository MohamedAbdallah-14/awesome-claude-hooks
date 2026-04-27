# Compatibility matrix

Operational metadata for every hook. Generated from `hooks.registry.yaml`.

| Hook | Event | Blocks? | Network? | Writes files? | Platforms | Tests |
|------|-------|---------|----------|----------------|-----------|-------|
| [`ai-code-review`](../hooks/ai/ai-code-review.sh) | `PostToolUse` | — | ✅ | — | macos, linux, wsl | — |
| [`ai-commit-message`](../hooks/ai/ai-commit-message.sh) | `Stop` | — | ✅ | — | macos, linux, wsl | — |
| [`ai-migration-safety`](../hooks/ai/ai-migration-safety.sh) | `PreToolUse` (`Bash`) | ✅ | ✅ | — | macos, linux, wsl | ✅ |
| [`ai-pr-description`](../hooks/ai/ai-pr-description.sh) | `Stop` | — | ✅ | — | macos, linux, wsl | — |
| [`ai-security-scan`](../hooks/ai/ai-security-scan.sh) | `PostToolUse` | — | ✅ | — | macos, linux, wsl | — |
| [`auto-changelog`](../hooks/automation/auto-changelog.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`auto-format-on-save`](../hooks/automation/auto-format-on-save.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | ✅ |
| [`auto-git-commit`](../hooks/automation/auto-git-commit.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`auto-prettier`](../hooks/automation/auto-prettier.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | ✅ |
| [`auto-push`](../hooks/automation/auto-push.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`auto-run-tests`](../hooks/automation/auto-run-tests.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | ✅ |
| [`auto-update-readme`](../hooks/automation/auto-update-readme.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | ✅ |
| [`inject-docker-status`](../hooks/context/inject-docker-status.sh) | `PreToolUse` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`inject-env-summary`](../hooks/context/inject-env-summary.sh) | `Stop` | — | — | ✅ | macos, linux | ✅ |
| [`inject-file-history`](../hooks/context/inject-file-history.sh) | `PreToolUse` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`inject-git-context`](../hooks/context/inject-git-context.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`inject-package-info`](../hooks/context/inject-package-info.sh) | `PreToolUse` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`inject-recent-commits`](../hooks/context/inject-recent-commits.sh) | `PreToolUse` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`inject-test-results`](../hooks/context/inject-test-results.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`inject-typescript-errors`](../hooks/context/inject-typescript-errors.sh) | `PreToolUse` | — | — | ✅ | macos | ✅ |
| [`budget-alert`](../hooks/cost/budget-alert.sh) | `PostToolUse` | — | — | ✅ | macos, linux | ✅ |
| [`daily-usage-report`](../hooks/cost/daily-usage-report.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | — |
| [`log-bash-history`](../hooks/cost/log-bash-history.sh) | `PostToolUse` (`Bash`) | — | — | ✅ | macos, linux, wsl | ✅ |
| [`log-tool-usage`](../hooks/cost/log-tool-usage.sh) | `PostToolUse` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`session-timer`](../hooks/cost/session-timer.sh) | `PreToolUse` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`aws-prod-guard`](../hooks/devops/aws-prod-guard.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`db-migration-guard`](../hooks/devops/db-migration-guard.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos | ✅ |
| [`docker-prod-guard`](../hooks/devops/docker-prod-guard.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`github-actions-validator`](../hooks/devops/github-actions-validator.sh) | `PreToolUse` (`Write`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`infra-audit-log`](../hooks/devops/infra-audit-log.sh) | `PostToolUse` (`Bash`) | — | — | ✅ | macos, linux, wsl | ✅ |
| [`kubernetes-prod-guard`](../hooks/devops/kubernetes-prod-guard.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`terraform-destroy-guard`](../hooks/devops/terraform-destroy-guard.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`ascii-confetti`](../hooks/fun/ascii-confetti.sh) | `Stop` | — | — | ✅ | linux | ✅ |
| [`break-reminder`](../hooks/fun/break-reminder.sh) | `Stop` | — | — | ✅ | macos, linux | ✅ |
| [`motivational-quote`](../hooks/fun/motivational-quote.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`session-stats`](../hooks/fun/session-stats.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`auto-create-branch`](../hooks/git/auto-create-branch.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | — |
| [`auto-resume-from-stash`](../hooks/git/auto-resume-from-stash.sh) | `SessionStart` (`resume`) | — | — | ✅ | macos, linux, wsl | ✅ |
| [`conflict-detector`](../hooks/git/conflict-detector.sh) | `PreToolUse` (`Edit|Write|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`pr-description-gen`](../hooks/git/pr-description-gen.sh) | `PostToolUse` (`Bash`) | — | — | ✅ | macos, linux, wsl | — |
| [`protect-main-branch`](../hooks/git/protect-main-branch.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`stash-guard`](../hooks/git/stash-guard.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`validate-commit-message`](../hooks/git/validate-commit-message.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`desktop-notify`](../hooks/notifications/desktop-notify.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`discord-notify`](../hooks/notifications/discord-notify.sh) | `Stop` | — | ✅ | ✅ | macos, linux, wsl | ✅ |
| [`linux-notify`](../hooks/notifications/linux-notify.sh) | `Stop` | — | — | ✅ | macos, linux | ✅ |
| [`macos-notify`](../hooks/notifications/macos-notify.sh) | `Stop` | — | — | ✅ | macos | ✅ |
| [`pushover-notify`](../hooks/notifications/pushover-notify.sh) | `Stop` | — | ✅ | ✅ | macos, linux, wsl | ✅ |
| [`slack-notify`](../hooks/notifications/slack-notify.sh) | `Stop` | — | ✅ | ✅ | macos, linux, wsl | ✅ |
| [`sound-complete`](../hooks/notifications/sound-complete.sh) | `Stop` | — | — | ✅ | macos, linux | ✅ |
| [`sound-error`](../hooks/notifications/sound-error.sh) | `PostToolUse` | — | — | ✅ | macos, linux | ✅ |
| [`telegram-notify`](../hooks/notifications/telegram-notify.sh) | `Stop` | — | ✅ | ✅ | macos, linux, wsl | ✅ |
| [`terminal-title`](../hooks/notifications/terminal-title.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`auto-approve-readonly`](../hooks/prompt/auto-approve-readonly.sh) | `PreToolUse` | — | — | ✅ | macos, linux, wsl | — |
| [`banned-words-enforcer`](../hooks/prompt/banned-words-enforcer.sh) | `UserPromptSubmit` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`no-ask-human-blocker`](../hooks/prompt/no-ask-human-blocker.sh) | `UserPromptSubmit` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`rate-limiter`](../hooks/prompt/rate-limiter.sh) | `PreToolUse` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`session-context-injector`](../hooks/prompt/session-context-injector.sh) | `UserPromptSubmit` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`cargo-clippy-gate`](../hooks/quality/cargo-clippy-gate.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`cargo-fmt-gate`](../hooks/quality/cargo-fmt-gate.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`dart-analyze`](../hooks/quality/dart-analyze.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | — |
| [`eslint-gate`](../hooks/quality/eslint-gate.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | — |
| [`go-vet`](../hooks/quality/go-vet.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | — |
| [`ktlint-gate`](../hooks/quality/ktlint-gate.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`php-pint-gate`](../hooks/quality/php-pint-gate.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`prettier-gate`](../hooks/quality/prettier-gate.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | — |
| [`python-lint`](../hooks/quality/python-lint.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | — |
| [`rubocop-gate`](../hooks/quality/rubocop-gate.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`suggest-fix-on-failure`](../hooks/quality/suggest-fix-on-failure.sh) | `PostToolUseFailure` (`Bash`) | — | — | ✅ | macos, linux | ✅ |
| [`swiftlint-gate`](../hooks/quality/swiftlint-gate.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`test-coverage-check`](../hooks/quality/test-coverage-check.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos | — |
| [`tsc-check`](../hooks/quality/tsc-check.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos, linux, wsl | — |
| [`validate-json-yaml`](../hooks/quality/validate-json-yaml.sh) | `PreToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`audit-bash-commands`](../hooks/security/audit-bash-commands.sh) | `PostToolUse` (`Bash`) | — | — | ✅ | macos, linux, wsl | ✅ |
| [`audit-file-writes`](../hooks/security/audit-file-writes.sh) | `PostToolUse` (`Write|Edit|MultiEdit`) | — | — | ✅ | macos | ✅ |
| [`block-dangerous-bash`](../hooks/security/block-dangerous-bash.sh) | `PreToolUse` (`Bash`) | ✅ | ✅ | ✅ | macos, linux, wsl | ✅ |
| [`block-secrets`](../hooks/security/block-secrets.sh) | `PreToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`block-system-paths`](../hooks/security/block-system-paths.sh) | `PreToolUse` (`Write|Edit|Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`check-npm-audit`](../hooks/security/check-npm-audit.sh) | `PreToolUse` (`Bash`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`permission-denied-logger`](../hooks/security/permission-denied-logger.sh) | `PermissionDenied` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`protect-dotenv`](../hooks/security/protect-dotenv.sh) | `PreToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`scan-sql-injection`](../hooks/security/scan-sql-injection.sh) | `PreToolUse` (`Write|Edit|MultiEdit`) | ✅ | — | ✅ | macos, linux, wsl | ✅ |
| [`context-threshold-guard`](../hooks/session/context-threshold-guard.sh) | `UserPromptSubmit` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`env-file-injector`](../hooks/session/env-file-injector.sh) | `SessionStart` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`log-tool-failures`](../hooks/session/log-tool-failures.sh) | `PostToolUseFailure` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`precompact-backup`](../hooks/session/precompact-backup.sh) | `PreCompact` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`session-end-summary`](../hooks/session/session-end-summary.sh) | `SessionEnd` | — | — | ✅ | macos | ✅ |
| [`session-name-from-branch`](../hooks/session/session-name-from-branch.sh) | `SessionStart` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`session-start-context`](../hooks/session/session-start-context.sh) | `SessionStart` | — | — | ✅ | macos, linux, wsl | ✅ |
| [`session-summary`](../hooks/session/session-summary.sh) | `Stop` | — | — | ✅ | macos, linux, wsl | ✅ |
