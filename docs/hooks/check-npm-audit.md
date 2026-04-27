# `check-npm-audit`

> Source: [`hooks/security/check-npm-audit.sh`](../../hooks/security/check-npm-audit.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `warn` by default, `blocking` with opt-in
> Block toggle: `CLAUDE_NPM_AUDIT_BLOCK=1` enables blocking on existing critical CVEs (default `0` = warn only)

## Problem

Claude reaches for `npm install left-pad-utils-pro` halfway through a refactor. The package is fine, or it's typo-squatted, or it pulls in a transitive that has a known critical CVE filed two days ago. By the time anyone notices, the dep is locked into `package-lock.json` and the next CI run propagates it across every developer's machine.

This hook surfaces a reminder on every install, and optionally blocks installs into a project that already has open critical vulnerabilities.

## What it catches

| Command | Behavior |
|---------|----------|
| `npm install <pkg>` / `npm i <pkg>` | Reminder to run `npm audit` after install |
| `yarn add <pkg>` | Same |
| `pnpm add <pkg>` | Same |
| Any of the above with `CLAUDE_NPM_AUDIT_BLOCK=1` and existing critical CVEs in `package.json` | **Blocked** until criticals are resolved |
| Anything else | Allowed unconditionally |

The blocking mode runs `npm audit --json` in the cwd and parses `metadata.vulnerabilities.critical`. If it's > 0, the install is denied.

## Before

Claude wants to run:

```
npm install some-random-utility
```

In warn mode the install proceeds, but Claude sees a reminder on stdout. In block mode with existing criticals, Claude never runs the command.

## After

Warn mode (default) — stdout reminder, action proceeds:

```
[check-npm-audit] Installing some-random-utility via npm. Remember to run `npm audit` afterwards to check for new vulnerabilities.
```

Block mode with existing criticals — Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: npm audit found 2 critical vulnerability/vulnerabilities in the current project before adding 'some-random-utility'. Run 'npm audit' and resolve critical issues before installing new packages. Unset CLAUDE_NPM_AUDIT_BLOCK to downgrade to a warning."
  }
}
```

Claude can then run `npm audit fix` or pin a safe version before retrying.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/security/check-npm-audit.sh"
          }
        ]
      }
    ]
  }
}
```

Or as part of the `security` profile:

```bash
bash scripts/install.sh --profile=security --global
```

## Test locally

```bash
# Warn mode (default)
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm install lodash"}}' \
  | bash hooks/security/check-npm-audit.sh; echo "exit: $?"
```

Expected: exit `0`, stdout reminder line, no JSON deny.

```bash
# Block mode (needs a project with criticals — usually a no-op in clean repos)
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm install lodash"}}' \
  | CLAUDE_NPM_AUDIT_BLOCK=1 bash hooks/security/check-npm-audit.sh; echo "exit: $?"
```

Expected: exit `0`. JSON deny only if `npm audit` reports critical vulnerabilities in the cwd.

The repo's bats suite covers this hook in [`tests/security/check-npm-audit.bats`](../../tests/security/check-npm-audit.bats).

## Bypass

This hook is warn-only by default — there is nothing to bypass.

To enable blocking, set `CLAUDE_NPM_AUDIT_BLOCK=1`. To go back to warn mode, unset it. The block trips only when `npm audit` finds existing criticals; a clean audit is silent.

## Safety notes

- No network calls in warn mode. Block mode runs `npm audit`, which contacts the npm registry.
- Reads stdin and (in block mode) `package.json` in the cwd. Does not write to disk.
- The package-name parser is regex-based; unusual install invocations (chained `&&`, scoped packages with weird flags) may produce a generic "package(s)" label instead of the exact name. The decision logic is unaffected.
- Block mode skips silently if `npm` is not on `PATH` or `package.json` is absent. It will not lock you out of a fresh project scaffold.
