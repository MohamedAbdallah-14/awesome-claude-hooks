# Roadmap

What's next, what's deliberately not next, and what's never going to be.

## Done (0.3.0 → 0.4.0)

- Spec-aligned blocking output: every PreToolUse blocker emits `hookSpecificOutput.permissionDecision="deny"` and exits 0. The deny reason actually reaches Claude now.
- All 28 official events recognized by the installer + linter. No silent fallback.
- `hooks.registry.yaml` is the single source of truth. `docs/hooks.md`, `docs/events.md`, `docs/compatibility.md` regenerate from it.
- `--profile` system in the installer with 8 curated bundles.
- bats coverage for every blocking hook in `security/`, `quality/`, `git/`, `devops/`, and `ai/`.
- Hero docs for top 26 hooks under `docs/hooks/`.
- `SECURITY_MODEL.md` with hook risk levels and review guidance.
- `scripts/new-hook.sh` scaffold and `scripts/hook-doctor.sh` validator.
- Bash 3.2 syntax CI matrix for the hooks themselves (scripts/ stay bash 4+).
- GitHub Discussions enabled, CODEOWNERS set, Dependabot auto-merge for safe bumps, lychee link checks, registry-drift CI.

## On deck

- Per-hook latency benchmark in CI. The contract guides "fast hooks"; we should measure.
- A small `claude-hooks` shell wrapper distributed via Homebrew tap so users don't have to clone the repo to install.
- Brand-LoRA / illustration assets for the README and OG image.
- Submission to awesome-claude-code as a curated entry under "Hooks".
- More language-specific quality gates: rust (`cargo clippy`/`cargo fmt`), kotlin, swift.
- A `claude-code-hooks` linter for *user* `~/.claude/settings.json` files (extended `hook-doctor`).

### Event coverage gaps — proposed hooks

Backlog grouped by the uncovered Claude Code event each hook fills. We currently ship hooks for ~9 of 28 events; the entries below close the biggest remaining blank spots. Sources at the end of the section.

**`PermissionDenied` (1 hook today: `permission-denied-logger`)**
- `permission-denied-retry-readonly` — `PermissionDenied` (matcher: `Read|Glob|Grep`): set `retry: true` for inert read tools so denials don't dead-end the loop.

**`SessionEnd` (1 hook today: `session-end-summary`)**
- `session-end-cleanup` — `SessionEnd`: delete stale tmp files and kill orphaned background processes spawned during the session.

**`CwdChanged` (0 hooks today)**
- `cwd-change-context` — `CwdChanged`: inject project context (name from `package.json`/`Cargo.toml`/`pyproject.toml`) when Claude `cd`s into a new repo.

**`SubagentStart` / `SubagentStop` (0 hooks today)**
- `subagent-budget-guard` — `SubagentStart`: block subagent spawns once a per-session budget is exceeded; logs to `~/.claude/subagent-budget.log`.
- `subagent-result-archiver` — `SubagentStop`: archive each subagent's `result_summary` to a per-session JSONL for multi-agent debugging.

**`Notification` / `StopFailure` (0 hooks today)**
- `notification-aggregator` — `Notification`: dedupe and rate-limit Claude Code notifications (collapse identical permission prompts within N seconds).
- `stop-failure-alert` — `StopFailure`: desktop notification on rate-limit/billing/auth errors so silent 429s don't strand a session.

**`PreCompact` (extending coverage)**
- `precompact-context-snapshot` — `PreCompact`: save the most recent N user messages + tool decisions to a markdown file before compaction; targeted recovery vs. our existing whole-transcript backup.

**`WorktreeCreate` / `WorktreeRemove` (0 hooks today)**
- `worktree-bootstrap` — `WorktreeCreate`: run `npm ci` / `uv sync` / `bundle install` in new worktrees; idempotent and lockfile-aware.
- `worktree-archive-on-remove` — `WorktreeRemove`: tar the worktree (or diff against `main`) before deletion to catch uncommitted work.

**`InstructionsLoaded` (0 hooks today)**
- `instructions-loaded-audit` — `InstructionsLoaded`: log every `CLAUDE.md` / rules file loaded (path, reason, parent) for compliance auditability.

**`ConfigChange` (0 hooks today)**
- `config-change-guard` — `ConfigChange`: block `permissions.defaultMode` flips to `auto`/`acceptAll` without an env-var bypass.

**`FileChanged` (0 hooks today)**
- `file-changed-env-reload` — `FileChanged` (matcher: `.envrc|.env`): re-export env vars to `$CLAUDE_ENV_FILE` when `.env`/`.envrc` changes mid-session.

**`TaskCreated` / `TaskCompleted` (0 hooks today)**
- `task-naming-validator` — `TaskCreated`: reject tasks whose name doesn't match a configured regex (e.g. `<scope>-<verb>-<noun>`).
- `task-completion-checklist` — `TaskCompleted`: block completion if `.claude/done-criteria.md` has unchecked items.

Sources: disler/claude-code-hooks-mastery, CC Notify, Claude Code event spec examples, community patterns. See research notes accompanying the proposals.

## Considered, not doing

- An npm/pip package. The repo is shell scripts. A package wrapper buys nothing the clone-and-symlink flow doesn't already give.
- A custom badge generator service. Shields.io covers everything we need.
- Mock-webhook integration tests for `slack-notify` / `discord-notify` / `telegram-notify`. The cost of running a fake HTTP server in CI exceeds the value of testing a single `curl -X POST`.

## Never

- Bundling hooks that require root or sudo. Hooks run with the user's permissions; that's the contract. If your hook needs root, it doesn't belong here.
- Hooks that phone home to a service we control. The repo is CC0; nothing should give us telemetry.
- Hooks that auto-update themselves. The user reviews diffs and pulls — that's the trust model.

If you want to push the roadmap, file an issue with the "new-hook" template or open a PR.
