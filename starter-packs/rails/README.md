# Rails Starter Pack

Pre-configured Claude Code hooks and project instructions for Ruby on Rails applications.

## What's included

**settings.json hooks**
- Pre-Bash: blocks hardcoded secrets, protects `.env` from mutation, blocks dangerous shell commands (e.g., `rm -rf`), guards against running migrations outside a safe context, and prevents direct commits to `main`/`master`.
- Pre-Write: audits every file write, validates JSON and YAML syntax before saving, and scans new code for SQL injection patterns before it lands on disk.
- Post-Write: runs an AI code review on every saved file, catching Rails anti-patterns (missing strong params, unsafe queries, misused callbacks) before they reach review.
- On stop: macOS desktop notification when the session ends, injects current git context for the next prompt, auto-updates the changelog, and logs total session time.

**CLAUDE.md rules**
- `bin/rails` and `bundle exec` enforced — no accidental version mismatches from system gems.
- RSpec-only testing with FactoryBot; no raw fixtures in new tests.
- `db/schema.rb` is read-only — all schema changes go through migrations with working `down` methods.
- Strong params required; `permit!` is banned.
- RuboCop must pass clean before any commit.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your Rails project root.
2. Copy `CLAUDE.md` to your project root.
3. Hooks assume `~/.claude/hooks/hooks` as the base path. If you cloned the hooks repo elsewhere, replace that prefix throughout `settings.json`.
4. Adjust the RuboCop and RSpec paths in `CLAUDE.md` if your project uses a non-standard layout.
