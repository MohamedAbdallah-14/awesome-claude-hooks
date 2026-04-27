---
description: Install a curated hook profile. Always dry-runs first, asks for confirmation, then installs.
argument-hint: <profile>
allowed-tools: Bash
---

Install the hook profile named `$ARGUMENTS` to the user's global Claude Code settings.

**Validate `$ARGUMENTS` before running any shell invocation.** The argument is interpolated into `bash` commands; do not skip this step.

Steps:

0. **Validation gate:** confirm `$ARGUMENTS` matches the safe token pattern `^[a-zA-Z0-9_-]+$`. If it doesn't, refuse to construct any command, run `bash scripts/install.sh --list-profiles`, and ask the user to pick a real profile. Also confirm the value appears in that list before proceeding.

1. Run `bash scripts/install.sh --profile=$ARGUMENTS --global --dry-run`. Show the user exactly which hooks would be added and where the settings file would be written.

2. Ask the user to confirm. If they say yes, run `bash scripts/install.sh --profile=$ARGUMENTS --global` (no dry-run).

3. After install, run `bash scripts/hook-doctor.sh` to confirm the resulting `~/.claude/settings.json` is valid and every command path resolves.

4. Tell the user to restart Claude Code so the new hooks load.

If `$ARGUMENTS` is empty or invalid (`bash scripts/install.sh --list-profiles` doesn't show it), bail and run `--list-profiles` so the user can pick a real one.
