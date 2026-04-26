---
description: Install a curated hook profile. Always dry-runs first, asks for confirmation, then installs.
argument-hint: <profile>
allowed-tools: Bash
---

Install the hook profile named `$ARGUMENTS` to the user's global Claude Code settings.

Steps:

1. Run `bash scripts/install.sh --profile=$ARGUMENTS --global --dry-run`. Show the user exactly which hooks would be added and where the settings file would be written.

2. Ask the user to confirm. If they say yes, run `bash scripts/install.sh --profile=$ARGUMENTS --global` (no dry-run).

3. After install, run `bash scripts/hook-doctor.sh` to confirm the resulting `~/.claude/settings.json` is valid and every command path resolves.

4. Tell the user to restart Claude Code so the new hooks load.

If `$ARGUMENTS` is empty or invalid (`bash scripts/install.sh --list-profiles` doesn't show it), bail and run `--list-profiles` so the user can pick a real one.
