---
description: Validate ~/.claude/settings.json hook references against this repo's registry
allowed-tools: Bash, Read
---

Run `bash scripts/hook-doctor.sh` and summarize the report for the user.

The doctor reports:
- Hooks referenced by absolute path that no longer exist on disk.
- Hooks under unknown event names.
- Duplicated commands within the same event (would run the same hook multiple times).
- Hooks whose path is inside this repo but the file no longer matches its registry entry (event/matcher mismatch).
- Settings JSON that doesn't validate.

If errors are found:
1. List them grouped by severity (error / warn / info).
2. Propose specific fixes — exact `settings.json` edits or which hooks to remove.
3. Offer to apply the fixes if the user confirms. Use the Read + Edit tools on `~/.claude/settings.json`.

If clean, just say so.

For machine-readable output the user can pipe elsewhere, run `bash scripts/hook-doctor.sh --json`.
