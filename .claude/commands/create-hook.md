---
description: Scaffold a new hook conforming to the awesome-claude-hooks contract
argument-hint: <name> <category> [event] [matcher]
allowed-tools: Bash, Read
---

You are scaffolding a new hook for the awesome-claude-hooks repo.

The user passed: `$ARGUMENTS`. Parse it as: hook name (kebab-case), category (one of `ai automation context cost devops fun git notifications prompt quality security session`), optional event (default `PreToolUse`), optional matcher. The `hooks/_lib` directory exists but is internal-only (shared shell helpers) — it is not a valid `--category` value.

**Validate every parsed token before constructing any shell command.**
- `name` must match `^[a-z][a-z0-9-]+$`.
- `category` must be one of the 12 listed above.
- `event` (if present) must be one of the 28 events from `docs/hook-contract.md`.
- `matcher` (if present) must match `^[A-Za-z0-9|]+$`.
- If any token fails, refuse to run the scaffold and tell the user what's wrong.

Steps:

1. Once each token has been validated, run `bash scripts/new-hook.sh --name=<name> --category=<cat> --event=<event> --matcher='<matcher>' --description='<one-line description>' --bypass=<BYPASS_VAR> --style=B`. Pass each value individually — never splice the raw `$ARGUMENTS` string into the command. The bypass var name is hook-specific and not formulaic — pick something readable that describes the toggle. Existing hooks use shapes like `CLAUDE_ALLOW_FORCE_PUSH`, `CLAUDE_NPM_AUDIT_BLOCK`, `CLAUDE_STASH_GUARD_SKIP`. The `--style=B` flag picks the structured-JSON output shape, which is the right default for blocking hooks.

2. If the command succeeds, the new file lives at `hooks/<cat>/<name>.sh` and a placeholder bats test at `tests/<cat>/<name>.bats`. Open the new hook file and ask the user what logic they want inside.

3. Run `bash scripts/lint-hooks.sh` to confirm the new hook satisfies the contract.

4. Run `bats tests/<cat>/<name>.bats` to confirm the placeholder test passes.

5. Suggest a hero doc at `docs/hooks/<name>.md`. Use `docs/hooks/block-secrets.md` as the template.

If `bash scripts/new-hook.sh` is missing or fails, read `docs/hook-contract.md` and create the hook by hand using `hooks/security/block-secrets.sh` as a template.
