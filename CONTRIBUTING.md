# Contributing

## TL;DR

```bash
make install-deps   # shellcheck, bats-core, jq, pyyaml
make all            # registry + docs + lint + tests
```

If `make all` is green locally, CI will be green on Ubuntu and macOS. The full hook contract lives in [`docs/hook-contract.md`](docs/hook-contract.md). Read it before adding a hook.

## Three ways to contribute

1. **File an issue** using the [Propose a new hook](.github/ISSUE_TEMPLATE/new_hook.yml) template. The repo's scaffolder bot will validate the form, and on a green validation it will commit a contract-conformant skeleton to a `scaffold/<issue#>-<name>` branch and open a draft PR for you. You take it from the TODO markers.
2. **Open a PR** with a working hook, a bats test, and (ideally) a hero doc.
3. **Improve docs or starter packs** — fix a broken example, add a stack to [`starter-packs/`](starter-packs/), tighten a category README.

## Adding a new hook

### 1. Pick a category

Each category has its own conventions and existing hooks. Skim the matching section of [`docs/hooks.md`](docs/hooks.md) before you start — duplicates with slightly different env vars get rejected.

| Category | What belongs here |
|---|---|
| [`ai/`](docs/hooks.md#ai) | Hooks that call an LLM (review, scan, draft) |
| [`automation/`](docs/hooks.md#automation) | Side effects on tool use or session end |
| [`context/`](docs/hooks.md#context) | Inject information into Claude's context window |
| [`cost/`](docs/hooks.md#cost) | Usage tracking and budget controls |
| [`devops/`](docs/hooks.md#devops) | Guards for terraform / k8s / aws / docker / migrations |
| [`fun/`](docs/hooks.md#fun) | Low-stakes, clearly optional hooks |
| [`git/`](docs/hooks.md#git) | Git workflow enforcement and automation |
| [`notifications/`](docs/hooks.md#notifications) | Alerting humans — desktop, mobile, chat |
| [`prompt/`](docs/hooks.md#prompt) | UserPromptSubmit gates and rewriters |
| [`quality/`](docs/hooks.md#quality) | Static analysis, linting, formatting gates |
| [`security/`](docs/hooks.md#security) | Block, warn, or audit for risk |
| [`session/`](docs/hooks.md#session) | SessionStart, PreCompact, SessionEnd lifecycle |

If your hook doesn't fit any of these, open an issue first. Don't invent a category in a PR.

### 2. Scaffold it

```bash
bash scripts/new-hook.sh \
  --name=block-aws-billing-spike \
  --category=devops \
  --event=PreToolUse \
  --matcher='Bash' \
  --description='Blocks aws commands that touch billing-sensitive APIs' \
  --bypass=CLAUDE_ALLOW_BILLING \
  --style=B
```

The scaffold drops a contract-conformant hook stub into `hooks/<category>/<name>.sh` and a matching bats skeleton into `tests/<category>/<name>.bats`. Run with no flags for an interactive prompt.

Style A is `stderr + exit 2` (simple block). Style B is `stdout JSON + exit 0` (structured permission decision). Pick one and stay there — never both.

### 3. Implement the contract

The canonical contract is [`docs/hook-contract.md`](docs/hook-contract.md). It covers the file header, supported event names, the stdin/stdout/exit-code contract, dependency handling, the bypass-env-var convention, idempotency rules, and the test requirements.

`bash scripts/lint-hooks.sh` enforces every rule in there. Run it locally before pushing.

### 4. Add a bats test

Tests live at `tests/<category>/<name>.bats`. Use the helpers in [`tests/test_helper.bash`](tests/test_helper.bash):

```bash
load '../test_helper'

@test "blocks OpenAI API key" {
  payload=$(pretool_payload Write /tmp/x.py "API_KEY='sk-...'")
  run_hook "$HOOK" "$payload"
  assert_blocked
}

@test "allows clean writes" {
  payload=$(pretool_payload Write /tmp/x.py "x = 1")
  run_hook "$HOOK" "$payload"
  assert_allowed
}
```

Tests are **required** for any hook under `security/`, `quality/`, `git/`, or `devops/` — anything that can block. A blocking hook without tests will not merge.

Cover at minimum:
- happy path (no block)
- block path
- bypass env var (if the hook has one)
- non-matching tool/event (hook should ignore it cleanly)

### 5. Add a hero doc (optional but encouraged)

For top-tier hooks, write a hero doc at `docs/hooks/<name>.md`. Use these as templates:

- [`docs/hooks/block-secrets.md`](docs/hooks/block-secrets.md)
- [`docs/hooks/terraform-destroy-guard.md`](docs/hooks/terraform-destroy-guard.md)

Sections: Problem, What it catches, Before/After, Install, Test locally, Bypass, Safety notes. Concrete and specific. No marketing.

### 6. Run `make all`

```bash
make all
```

That runs the registry generator, doc generator, contract linter, shellcheck, and bats. If it's green locally, CI will be green. If it's not, fix it before pushing — the same checks run on every PR.

## What to avoid

- **Network calls in `PreToolUse` hooks.** They're blocking. A DNS timeout adds latency to every tool call. Move network work to `PostToolUse`, `Stop`, or a backgrounded subprocess.
- **Assuming bash 4+ inside hooks.** macOS ships bash 3.2 by default. No associative arrays, no `${var,,}`, no `mapfile`. The CI matrix runs on macOS — code that needs bash 4 will fail.
- **Writing logs without rotation.** Hooks fire many times per session. An unbounded append to `~/.claude/logs/foo.log` becomes a multi-gigabyte file. Cap size or rotate.
- **Deny reasons that don't tell the model what to do instead.** `"Blocked"` is useless. `"Blocked: hardcoded secret. Move credentials to environment variables or a secrets manager. Set CLAUDE_ALLOW_SECRETS=1 to override for fixtures."` is useful — Claude can act on it.
- **Combining behaviors.** One hook per file. A script that notifies *and* logs *and* lints is three hooks.
- **External runtime dependencies.** Allowed: `bash`, `jq`, POSIX tools, optional platform tools (`osascript`, `notify-send`, `paplay`). Anything else needs a `command -v` check and a graceful `exit 0` if missing.

## Code review process

Every PR runs:

- `shellcheck -S warning` on all shell sources
- `scripts/lint-hooks.sh` — the hook-contract enforcer
- `bats -r tests`
- `lychee` link check against the docs
- `CodeRabbit` AI review (will pre-comment before a human looks)
- A registry-drift check that fails if `hooks.registry.yaml` and `docs/hooks.md` are out of sync

The required-checks aggregator must be green before merge. A maintainer reviews after CI passes. Squash-merge is the default — write commits for yourself, the merged history will be one commit per PR.

## Code of Conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
