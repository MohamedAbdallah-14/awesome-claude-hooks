# Rust Starter Pack

Drop-in `settings.json` for Rust crates and workspaces. Layers `safe-default` with security blocks and `main`-branch protection.

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands`.
- `git/protect-main-branch`.

**Pre-Edit/Write**
- `security/block-secrets` — file-write path.
- `quality/validate-json-yaml` — parse-check JSON/YAML (config, GitHub Actions). Note: this hook does not currently parse TOML, so `Cargo.toml` syntax errors will not be caught here.

**Post-Edit/Write**
- `security/audit-file-writes` — write log.

**Post-Bash**
- `context/inject-recent-commits`.

**SessionStart**
- `session/context-threshold-guard`.

**Stop**
- `notifications/desktop-notify`, `session/session-summary`, `context/inject-git-context`, `cost/log-tool-usage`.

## Missing: Rust-specific gates

There is no dedicated Rust quality hook in this repo yet — no `cargo-clippy-gate`, no `cargo-fmt-gate`, no `cargo-check-gate`. The Rust pack therefore relies on:

- `CLAUDE.md` rules to enforce `cargo check` / `cargo clippy -- -D warnings` / `cargo fmt` discipline.
- Your CI / pre-commit hooks for the actual cargo invocations.

**Follow-up:** add `quality/cargo-clippy-gate.sh` and `quality/cargo-fmt-gate.sh` (mirror `quality/go-vet.sh` and `quality/python-lint.sh`). Until then this pack is security + workflow only on the Rust side.

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/rust/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/rust/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=safe-default --global
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- Install `cargo-audit` (`cargo install cargo-audit`) so the workflow rules in `CLAUDE.md` are runnable.
