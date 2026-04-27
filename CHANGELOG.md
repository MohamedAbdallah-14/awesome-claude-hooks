# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.4.0] — 2026-04-27

### Added
- **11 new hooks (79 → 90).** Six quality gates for languages we didn't cover: `cargo-fmt-gate`, `cargo-clippy-gate` (Rust), `ktlint-gate` (Kotlin), `swiftlint-gate` (Swift), `rubocop-gate` (Ruby), `php-pint-gate` (PHP). All silently no-op when the underlying tool isn't on PATH. Five spec-coverage hooks for events the repo had zero coverage for: `log-tool-failures` and `suggest-fix-on-failure` (`PostToolUseFailure`), `permission-denied-logger` (`PermissionDenied`), `session-end-summary` (`SessionEnd`), and `auto-resume-from-stash` (`SessionStart` matcher `resume`).
- **bats coverage now 421 cases (was 170).** Every hook in `security/`, `quality/`, `git/`, `devops/`, `ai/`, `automation/`, `context/`, `cost/`, `notifications/`, `fun/`, `prompt/`, `session/` has at least one test. Tests use new `assert_blocked` / `assert_allowed` / `posttool_payload` / `assert_blocked_post` helpers in `tests/test_helper.bash`.
- **GitHub Pages browser** at <https://mohamedabdallah-14.github.io/awesome-claude-hooks/>. 820 lines of vanilla HTML+CSS+JS; filter by category, event, risk, profile, capability flags; full-text search; dark mode default; no external assets.
- **`docs/hooks/`** gains 20 hero docs (was 5) covering the highest-stakes hooks across security, git, devops, ai, quality, automation, prompt, session.
- **`docs/claude-code-versions.md`** — per-event minimum Claude Code version with hook counts. Versions cross-checked against the official changelog.
- **`scripts/new-hook.sh`** — interactive scaffold (377 lines) for new hooks. Validates name/category/event/style; refuses to overwrite; generates lint-passing header + bats placeholder.
- **`scripts/hook-doctor.sh`** — read-only validator (295 lines) that checks `~/.claude/settings.json` against the registry. Reports missing files, unknown events, dup commands, registry drift. Bash 3.2 compatible. `--json` output.
- **`scripts/test-installer.sh`** — smoke-test for `--dry-run` across all 8 profiles.
- **`make doctor`** — environment diagnostic (toolchain versions + settings validation + bash-3.2 compat check).
- **`bash-3.2-compat` CI job** — builds bash 3.2 from source (cached), `bash -n`s every hook. `lint-hooks.sh` warns (not errors) on `declare -A` / `mapfile` / `coproc` / case-modification parameter expansion.
- **`.claude/commands/`** — slash commands for `/create-hook`, `/hook-doctor`, `/list-profiles`, `/install-profile`.
- Issue templates: `spec_drift.yml` for divergence-from-spec reports. Discussion templates: `help.yml` and `show-and-tell.yml`.
- `ROADMAP.md` "On deck" backlog of 15 hooks grouped by uncovered events (covers `PermissionDenied`, `CwdChanged`, `SubagentStart`/`Stop`, `Notification`, `StopFailure`, `WorktreeCreate`/`Remove`, `InstructionsLoaded`, `ConfigChange`, `FileChanged`, `TaskCreated`/`Completed`).
- `SHOWCASE.md` scaffold; top-level `CLAUDE.md` so contributors using Claude Code on this repo get the right priors.

### Changed
- README rewritten around user intent. Headline leads with the hook count + spec alignment + one-command install. "Browse all hooks" callout near the top points at the Pages site + `docs/hooks.md`. 226 lines (was 277).
- Per-category `hooks/<cat>/README.md` rewritten for all 12 categories. Each delegates to the registry + `docs/hooks.md` instead of duplicating tables. ~80% size reduction on the 8 that already existed; 4 new ones (ai, devops, prompt, session).
- All 11 starter packs updated. Settings JSON paths now match the README's quick-start clone target. Each pack composes `safe-default` core + stack-specific gates. Documented gaps where a stack lacks a quality gate.
- CONTRIBUTING.md rewritten around the new contribution flow: scaffold → contract pointer → bats → optional hero doc → `make all`. Trimmed ~60 lines of contract material now delegated to `docs/hook-contract.md`.
- All third-party GitHub Actions pinned to commit SHA across CI / labeler / lychee / dependabot-automerge / pages / release / stale.
- Hook headers normalized: every hook that reads a `CLAUDE_*` env var now has a `# Config (env vars):` block. `terminal-title` Event header fixed (was the non-canonical `PreToolUse AND Stop`). `ai-migration-safety` Event header fixed (was the non-canonical `PreToolUse  (BLOCKING)` with a separate `# Matcher:` line).

### Fixed
- `hooks/ai/ai-code-review.sh` and `ai-security-scan.sh` were reading `tool_input.path` instead of `tool_input.file_path`. Hooks would never have fired on real Write events. Now read `.file_path` with `.path` fallback.
- `hooks/devops/aws-prod-guard.sh`: BSD-grep regex bug (character class `[-_]` placement misread as an invalid range) and readonly-verb pattern matching trailing `--user-name test` style tokens. Tightened readonly detection to require the verb right after `aws <service>`; dropped ambiguous verbs `test`/`validate`/`preview`/`estimate`/`forecast`/`explain` from the readonly list.
- `hooks/security/scan-sql-injection.sh`: JS template-literal regex `\$\{` collapsed to `$\{` after one round of bash unescaping; ERE then read `$` as the end-of-line anchor and the rule never matched. Replaced with `[$]\{`.
- `hooks/ai/ai-migration-safety.sh`: dead code path. Built `PROMPT` via `jq -Rs` from empty stdin, then immediately overwrote it. Dropped the dead first invocation.
- `hooks/devops/db-migration-guard.sh`: had no env-var bypass, in violation of the contract. Added `CLAUDE_ALLOW_DB_DESTRUCTIVE`.
- `hooks/cost/daily-usage-report.sh`: used `declare -A` (bash 4 only). Rewrote per-tool / per-file counting to delegate to awk so the hook works under macOS `/bin/bash` 3.2.
- `hooks/prompt/auto-approve-readonly.sh`: matcher listed `TodoRead`, which isn't a real Claude Code tool name. Removed.
- `scripts/install.sh:get_hook_meta()`: matcher regex required quotes around the matcher token, but `xargs` upstream stripped them, crashing the installer on every hook with a `matcher` header. Now accepts both quoted and bare matcher tokens.

## [0.3.0] — 2026-04-27

### Changed (breaking for hook authors)
- All 18 PreToolUse blocking hooks switched from `{"decision":"block","reason":"..."} + exit 2` to the official structured shape `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}} + exit 0`. Per the Claude Code docs, JSON output is processed only on exit 0; the previous shape made the reason invisible to Claude. Reasons now reach the model.
- `scripts/install.sh:get_hook_meta()` and `scripts/lint-hooks.sh` recognise all 28 official hook events. The installer fails loudly on an unknown event instead of silently defaulting to `Stop`. The `# Event` field in every hook header is validated against the full set.
- Tests now use `assert_blocked` / `assert_allowed` helpers (in `tests/test_helper.bash`) that check the new JSON contract instead of asserting exit code 2.

### Added
- `hooks.registry.yaml` (+ JSON twin) as the single source of truth for the catalog. Generated by `scripts/build-registry.py`.
- `scripts/render-docs.py` regenerates `docs/hooks.md` (by category), `docs/events.md` (by event), and `docs/compatibility.md` (operational matrix: blocks / network / writes / platforms / tests).
- `scripts/install.sh --profile=<name>` and `--list-profiles`. Profiles are read from the registry. Bundled profiles: `safe-default`, `security`, `quality`, `team`, `devops`, `solo-dev`, `notifications`, `ai-assisted`.
- `SECURITY_MODEL.md`: threats covered, threats not covered, six hook risk levels (passive / contextual / modifying / blocking / networked / privileged), review guidance.
- Hero docs under `docs/hooks/` for the five highest-stakes hooks: `block-secrets`, `block-dangerous-bash`, `protect-dotenv`, `validate-json-yaml`, `terraform-destroy-guard`. Each one walks Problem → Before → After → Install → Test → Bypass → Safety.
- `docs/hook-contract.md` rewritten with the full I/O contract (stderr+exit-2 vs stdout-JSON+exit-0), worked examples for `PreToolUse`/`SessionStart`/`UserPromptSubmit`/`PostToolUse`, and the universal output fields (`continue`, `stopReason`, `suppressOutput`, `systemMessage`).
- README rewritten around user intent (I want safer sessions / better quality / team defaults / notifications / devops / AI review / solo-dev) instead of by implementation category. New "What this modifies" trust block.
- New CI job `registry-drift` regenerates the registry + docs and fails if anything changed. Required for branch protection alongside shellcheck, hook-contract-lint, and bats.
- GitHub repo metadata: description, homepage, 11 topics (`claude-code`, `claude`, `anthropic`, `hooks`, `developer-tools`, `ai-coding`, `shell`, `security`, `devtools`, `automation`, `awesome-list`).
- `Makefile` gains `registry`, `docs`, and `all` runs registry → docs → lint → tests in one command.
- `new_hook.yml` issue-template event dropdown lists all 28 official events.

### Fixed
- `terraform-destroy-guard` warn-mode emission for `terraform apply -destroy` was a no-op JSON to stderr; replaced with a plain stderr warning so the message is actually logged.

### Added
- CI: shellcheck, hook contract linter, and bats tests on Ubuntu + macOS.
- `docs/hook-contract.md` — every hook's required header fields, I/O contract, and bypass naming.
- `scripts/lint-hooks.sh` — enforces the contract; runs in CI and pre-commit.
- `tests/` — bats coverage for security and quality hooks (block-secrets, block-dangerous-bash, protect-dotenv, block-system-paths, validate-json-yaml).
- `.shellcheckrc` and `.pre-commit-config.yaml`.
- SPDX `CC0-1.0` headers on every shell script.
- GitHub issue and PR templates.
- `VERSION` file and release workflow.

### Changed
- `scripts/install.sh`: auto-discovers categories instead of hardcoding seven of them.
- `hooks/security/protect-dotenv.sh`: no longer false-positives on `.env.example`, `.env.sample`, `.env.template`, `.env.dist`.
- `hooks/quality/test-coverage-check.sh`: collapsed shadowed dart pattern.
- `hooks/prompt/auto-approve-readonly.sh`: corrected event from the non-existent `PermissionRequest` to `PreToolUse` with a `Read|Glob|Grep|LS|WebSearch|WebFetch|TodoRead` matcher.
- README count adjusted to the actual 79 hooks (78 prior + the new cross-platform `desktop-notify`).

### Fixed
- `hooks/git/auto-create-branch.sh`: malformed install snippet (stray indentation broke the JSON).
- Headers added to 13 hooks under `hooks/devops/` and `hooks/session/` that were missing the documented contract fields.

## [0.1.0] — 2026-04-26

### Added
- Initial release: 79 production-ready hooks across 12 categories, 11 stack-specific starter packs, interactive installer.
