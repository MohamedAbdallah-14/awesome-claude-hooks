# Next.js Starter Pack

Pre-configured Claude Code hooks and project instructions for Next.js 14+ with App Router.

## What's included

**settings.json hooks**
- Pre-edit: blocks secrets and `.env` mutations, validates JSON/YAML, detects merge conflicts, protects `main`/`master` from direct commits.
- Post-edit: runs ESLint, TypeScript type-check, and Prettier on every file you touch. Injects recent git commits into context after Bash calls.
- On stop: desktop notification, updates terminal title, prints git context and session stats.

**CLAUDE.md rules**
- Server Components by default; `'use client'` only where strictly needed.
- No `any`, no `console.log` in production, named exports only.
- Zod for all external data validation; Tailwind for all styling.
- Check `components/` for existing components before creating new ones.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your project root.
2. Copy `CLAUDE.md` to your project root.
3. Replace `$HOOKS_DIR` in `settings.json` with the absolute path to the cloned `awesome-claude-hooks/hooks/` directory.
4. Adjust the CLAUDE.md sections that say "adjust as needed" to match your actual project structure.
