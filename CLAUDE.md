# CLAUDE.md

You are working on awesome-claude-hooks, a production-ready hook library for Claude Code.

## Repo layout

- `hooks/<category>/` — every hook is a single `.sh` file.
- `tests/<category>/<hook>.bats` — bats tests for every blocking hook.
- `docs/hook-contract.md` — the contract every hook must satisfy.
- `hooks.registry.yaml` — single source of truth, generated.
- `scripts/build-registry.py` + `scripts/render-docs.py` — regenerators.
- `scripts/install.sh` — installer with `--profile` / `--category` / `--all`.
- `scripts/lint-hooks.sh` — header validator, runs in CI.
- `Makefile` — `make all` runs registry → docs → lint → tests.

## When asked to add a new hook

1. Read `docs/hook-contract.md` first.
2. Use `bash scripts/new-hook.sh --name=... --category=...` to scaffold (or copy an existing hook).
3. Implement the logic.
4. Add a bats test under `tests/<category>/<name>.bats` using the helpers from `tests/test_helper.bash`.
5. Run `make all`. Iterate until green.
6. The registry will pick the new hook up automatically.

## When asked to modify a hook

- Don't change the I/O contract (event, output JSON shape) without checking `docs/hook-contract.md`.
- Blocking PreToolUse hooks emit `{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"..."}}` and exit 0. Never exit 2 with JSON — Claude ignores it.
- Add or update a bats test for the change.

## Style

- shell: bash 4+ for `scripts/`, bash 3.2-compat for `hooks/`. `shellcheck -S warning` must pass.
- markdown: terse, technical, no marketing slop. Read `docs/hooks/block-secrets.md` for voice.
- commits: conventional commits. No "comprehensive solution", no "robust implementation".

## CI

- shellcheck, hook contract lint, registry/docs drift, bats (Ubuntu + macOS), lychee link check, CodeRabbit.
- Branch protection requires the `required checks` aggregator job.
