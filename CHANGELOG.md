# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [SemVer](https://semver.org/).

## [Unreleased]

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
- README count adjusted to the actual 78 hooks.

### Fixed
- `hooks/git/auto-create-branch.sh`: malformed install snippet (stray indentation broke the JSON).
- Headers added to 13 hooks under `hooks/devops/` and `hooks/session/` that were missing the documented contract fields.

## [0.1.0] — 2026-04-26

### Added
- Initial release: 78 production-ready hooks across 12 categories, 11 stack-specific starter packs, interactive installer.
