# Android Starter Pack

Pre-configured Claude Code hooks and project instructions for Android (Kotlin) apps.

## What's included

**settings.json hooks**
- Pre-Bash: blocks secrets and `.env` mutations, blocks dangerous shell commands, prevents direct pushes to the main branch.
- Pre-Write: audits file writes for sensitive paths, validates any JSON or YAML files before they land.
- Post-Write: runs an AI code review pass on every written file.
- On stop: macOS desktop notification, git context summary, session timer, auto-changelog update.

**CLAUDE.md rules**
- `./gradlew` enforced — no bare `gradle` invocations.
- MVVM + Repository architecture with coroutines and `Flow` for async work.
- Null safety enforced: `!!` requires a documented invariant.
- No business logic in `Activity` or `Fragment`.
- Secrets (keystore, `google-services.json`, API keys) must never be committed.
- ProGuard rules updated when adding reflection-dependent libraries.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your Android project root.
2. Copy `CLAUDE.md` to your project root.
3. Hooks use `~/.claude/hooks/hooks` as the base path — the default clone location. If you cloned the hooks repo elsewhere, replace that prefix with your actual path.
4. Optional: add the OWASP Dependency Check Gradle plugin to get CVE scanning via `./gradlew dependencyCheckAnalyze`.
