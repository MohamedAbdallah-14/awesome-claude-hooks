# Rust Starter Pack

Pre-configured Claude Code hooks and project instructions for Rust projects.

## What's included

**settings.json hooks**
- Pre-Bash: blocks hardcoded secrets, blocks dangerous shell commands, and prevents direct commits to `main`/`master`.
- Pre-Write: audits every file write and validates JSON/TOML/YAML before saving — useful for `Cargo.toml` and config file edits.
- Post-Write: runs an AI code review for Rust-specific issues (missing `SAFETY` comments, `unwrap()` in library code, error-handling gaps), then a dedicated AI security scan that flags unsafe patterns, dependency risks, and memory issues.
- Post-Bash: logs every shell command to an infra audit trail — useful when `cargo build` or custom scripts touch the filesystem or network.
- On stop: macOS desktop notification, git context injection for the next prompt, session duration log, and a tool-usage cost breakdown.

**CLAUDE.md rules**
- `cargo check` before `cargo build` — enforced to keep the inner loop fast.
- `cargo clippy -- -D warnings` and `cargo fmt` must pass clean before any commit.
- `unwrap()` banned in library code; `?`, `thiserror`, and `anyhow` are the required pattern.
- Every `unsafe` block requires a `// SAFETY:` comment.
- `cargo audit` required before adding new dependencies.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your Rust project root.
2. Copy `CLAUDE.md` to your project root.
3. Hooks assume `~/.claude/hooks/hooks` as the base path. If you cloned the hooks repo elsewhere, replace that prefix throughout `settings.json`.
4. Install `cargo-audit` if not present: `cargo install cargo-audit`.
