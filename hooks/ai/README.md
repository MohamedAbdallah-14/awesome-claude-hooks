# AI hooks

Hooks that call Claude Haiku (or any other model via API) to add a second pair of eyes during a session: lightweight code review, security scanning, commit-message suggestions, PR description drafts, and migration-safety checks. All five are advisory by default and skip silently when `ANTHROPIC_API_KEY` is unset, so they never block a session because of a missing credential.

These hooks make outbound network calls. Read [`SECURITY_MODEL.md`](../../SECURITY_MODEL.md) before enabling them on sensitive code.

## Hooks

- [`ai-code-review`](ai-code-review.sh) ([catalog](../../docs/hooks.md#ai)) — Sends each file write to Haiku for a 2-sentence review flagging only real bugs. Skips files over 100 lines.
- [`ai-security-scan`](ai-security-scan.sh) ([catalog](../../docs/hooks.md#ai)) — After writes to `.py`/`.js`/`.ts`/`.go`, asks Haiku for OWASP Top 10 issues. Injects findings only when something is found.
- [`ai-commit-message`](ai-commit-message.sh) ([catalog](../../docs/hooks.md#ai)) — At session end, suggests a Conventional Commits message when the last commit looks lazy. Advisory only.
- [`ai-pr-description`](ai-pr-description.sh) ([catalog](../../docs/hooks.md#ai)) — At session end, drafts a PR description from the branch's commits and saves it to `/tmp/claude-pr-draft.md`.
- [`ai-migration-safety`](ai-migration-safety.sh) ([catalog](../../docs/hooks.md#ai)) — Intercepts DB migration commands, asks Haiku if they're reversible, blocks only on `IRREVERSIBLE`.

## Install just this category

The `ai-assisted` profile maps to every hook here:

```bash
bash scripts/install.sh --profile=ai-assisted --global
```

Or install everything in this directory without the profile filter:

```bash
bash scripts/install.sh --category=ai --global
```

Both commands require `ANTHROPIC_API_KEY` to be set in your shell or in the `env` block of `settings.json`. Without it, every hook in this category is a no-op.
