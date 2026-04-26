# Next.js Starter Pack

Drop-in `settings.json` for Next.js 14+ App Router projects. Layers `safe-default` (audit + summary + context guard + desktop notify) with the JS/TS quality stack: ESLint, Prettier, `tsc --noEmit`, plus secret/dotenv guards and `main`-branch protection.

## Hooks included

**Pre-Bash**
- `security/block-secrets` — blocks shell commands echoing/piping secret-shaped strings.
- `security/protect-dotenv` — refuses writes targeting `.env*`.
- `security/block-dangerous-bash` — kills destructive shell patterns.
- `security/audit-bash-commands` — appends every Bash call to `~/.claude/audit/bash.log`.
- `git/protect-main-branch` — blocks direct commits/pushes to `main`/`master`.

**Pre-Edit/Write**
- `security/block-secrets` — file-write path for the same matcher.
- `quality/validate-json-yaml` — parses JSON/YAML before they hit disk.

**Post-Edit/Write**
- `quality/eslint-gate` — runs `eslint --fix` on the touched file.
- `quality/prettier-gate` — runs `prettier --write` on the touched file.
- `quality/tsc-check` — type-checks the touched file with the project `tsconfig.json`.
- `security/audit-file-writes` — logs every write target.

**Post-Bash**
- `context/inject-recent-commits` — recent commits back into context.

**SessionStart**
- `session/context-threshold-guard` — warns near context limit.

**Stop**
- `notifications/desktop-notify` — cross-platform desktop banner.
- `notifications/terminal-title` — sets terminal tab title with session state.
- `session/session-summary` — one-line session summary.
- `context/inject-git-context` — branch + dirty files for the next turn.

## Install

```bash
# Project-scoped
cp ~/.claude/awesome-hooks/starter-packs/nextjs/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/nextjs/CLAUDE.md ./CLAUDE.md
```

Or install the closest profile globally and copy this `CLAUDE.md`:

```bash
bash scripts/install.sh --profile=quality --global
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- `tsc-check.sh` requires `typescript` available locally (`npm install -D typescript`).
- The `CLAUDE.md` rules assume Tailwind, Zod, named exports — strip what doesn't apply.
