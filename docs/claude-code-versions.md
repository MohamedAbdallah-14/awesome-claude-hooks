# Claude Code version compatibility

awesome-claude-hooks aligns with the **current** official Claude Code hooks
spec at <https://code.claude.com/docs/en/hooks>. Hooks declare their event;
older Claude Code versions may not emit every event we list.

If you install a hook bound to an event your Claude Code version does not yet
emit, Claude Code silently ignores it — the hook never runs, and you get no
warning. This page maps each event to the earliest version we can confirm it
shipped in, based on the official changelog at
<https://code.claude.com/docs/en/changelog>.

## Minimum Claude Code version

**`2.1.105`** is the floor we recommend. That version covers every event
explicitly introduced in the public changelog window we could verify
(including `PreCompact`, the latest addition we have a dated entry for).

Lower versions will silently ignore hooks under newer events. If you're on a
version older than `2.1.78` (the earliest entry in the published changelog at
the time of writing), we cannot tell you which events you have — the
changelog does not go back that far.

Check your version with:

```bash
claude --version
```

## Events by version

The "Available since" column reflects what the official changelog at
<https://code.claude.com/docs/en/changelog> documents. Events marked
**unverified** existed before the published changelog window (`< 2.1.78`)
or were not called out in a dated changelog entry we could find — they are
listed in the current hooks reference, but we cannot pin them to a version
without speculating, so we don't.

`Hooks in this repo` is generated from `hooks.registry.json`.

| Event | Available since | Hooks in this repo |
|-------|-----------------|---------------------|
| PreToolUse | unverified (≤ 2.1.78) | 27 |
| PostToolUse | unverified (≤ 2.1.78) | 21 |
| PostToolUseFailure | unverified (≤ 2.1.78) | 0 |
| PostToolBatch | unverified | 0 |
| PermissionRequest | unverified (≤ 2.1.78) | 0 |
| PermissionDenied | 2.1.89 | 0 |
| Notification | unverified (≤ 2.1.78) | 0 |
| UserPromptSubmit | unverified (≤ 2.1.78) | 4 |
| UserPromptExpansion | unverified | 0 |
| SubagentStart | unverified | 0 |
| SubagentStop | unverified (≤ 2.1.78) | 0 |
| TaskCreated | 2.1.84 | 0 |
| TaskCompleted | unverified | 0 |
| Stop | unverified (≤ 2.1.78) | 23 |
| StopFailure | 2.1.78 | 0 |
| TeammateIdle | unverified | 0 |
| InstructionsLoaded | unverified | 0 |
| ConfigChange | unverified | 0 |
| CwdChanged | 2.1.83 | 0 |
| FileChanged | 2.1.83 | 0 |
| WorktreeCreate | unverified (enhanced 2.1.84) | 0 |
| WorktreeRemove | unverified | 0 |
| PreCompact | 2.1.105 | 1 |
| PostCompact | unverified | 0 |
| Elicitation | unverified | 0 |
| ElicitationResult | unverified | 0 |
| SessionStart | unverified (≤ 2.1.78) | 3 |
| SessionEnd | unverified (≤ 2.1.78, fixed 2.1.101) | 0 |

Total: 28 events, 79 hooks across 6 events currently in use.

### Notable behavioral changes

These aren't new events, but they changed how an existing event behaves —
worth knowing if a hook works for someone else but not for you:

- **2.1.85** — `PreToolUse` hooks gained `updatedInput` alongside
  `permissionDecision`, plus a conditional `if` field using permission rule
  syntax (e.g. `Bash(git *)`).
- **2.1.89** — `PreToolUse` gained the `"defer"` permission decision for
  headless sessions.
- **2.1.101** — `PreToolUse` payloads now carry absolute paths;
  `PermissionRequest` re-checks `updatedInput`; `SessionEnd` fires correctly
  when switching sessions via `/resume`; agent-type hooks fire when running
  as a main-thread agent via `--agent`; `UserPromptSubmit` gained
  `hookSpecificOutput.sessionTitle`.
- **2.1.105** — `PreCompact` hooks can now block compaction (`exit 2` or
  `{"decision":"block"}`).
- **2.1.119** — `PostToolUse` and `PostToolUseFailure` payloads now include
  `duration_ms` (tool execution time, excluding permission prompts and
  `PreToolUse` hooks).

## What to do if a hook doesn't fire

1. Confirm your Claude Code version: `claude --version`.
2. Check this table — if your version predates the "Available since" column
   for that event, the event isn't being emitted.
3. If your version is old, run `claude upgrade` (or your platform's
   equivalent — Homebrew, npm, etc.).
4. If the version is new enough, check `~/.claude/settings.json` for the
   matching `hooks.<EventName>` block, then run the hook manually with a
   sample payload to rule out a bug in the hook itself.

## Where event names came from

The full list of 28 events this repo recognizes is documented in
[`hook-contract.md`](hook-contract.md), which sources them from the
official hooks reference at <https://code.claude.com/docs/en/hooks>. The
linter in `scripts/lint-hooks.sh` rejects any header that uses an event
name outside that list.
