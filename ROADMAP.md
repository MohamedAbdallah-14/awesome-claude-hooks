# Roadmap

What's next, what's deliberately not next, and what's never going to be.

## Done (0.3.0 → 0.4.0)

- Spec-aligned blocking output: every PreToolUse blocker emits `hookSpecificOutput.permissionDecision="deny"` and exits 0. The deny reason actually reaches Claude now.
- All 28 official events recognized by the installer + linter. No silent fallback.
- `hooks.registry.yaml` is the single source of truth. `docs/hooks.md`, `docs/events.md`, `docs/compatibility.md` regenerate from it.
- `--profile` system in the installer with 8 curated bundles.
- bats coverage for every blocking hook in `security/`, `quality/`, `git/`, `devops/`, and `ai/`.
- Hero docs for top 15 hooks under `docs/hooks/`.
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

## Considered, not doing

- A standalone GitHub Pages site with search. The generated `docs/hooks.md` already does category and event browsing; full-text search is overkill at 79 hooks.
- An npm/pip package. The repo is shell scripts. A package wrapper buys nothing the clone-and-symlink flow doesn't already give.
- A custom badge generator service. Shields.io covers everything we need.
- Mock-webhook integration tests for `slack-notify` / `discord-notify` / `telegram-notify`. The cost of running a fake HTTP server in CI exceeds the value of testing a single `curl -X POST`.

## Never

- Bundling hooks that require root or sudo. Hooks run with the user's permissions; that's the contract. If your hook needs root, it doesn't belong here.
- Hooks that phone home to a service we control. The repo is CC0; nothing should give us telemetry.
- Hooks that auto-update themselves. The user reviews diffs and pulls — that's the trust model.

If you want to push the roadmap, file an issue with the "new-hook" template or open a PR.
