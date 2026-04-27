# Prompt hooks

Hooks that fire on `UserPromptSubmit` (and a couple on `PreToolUse`) to shape Claude's behaviour at the input boundary: prepend session context, auto-approve read-only tools, enforce banned phrasing, reinforce no-clarifying-question requests, and detect runaway tool loops.

These hooks don't change what Claude is asked; they augment context or change permission flow. None of them modify your prompt content.

## Hooks

- [`session-context-injector`](session-context-injector.sh) ([catalog](../../docs/hooks.md#prompt)) — Prepends a one-line context header (`[branch:... | CLAUDE.md:yes]`) to every prompt.
- [`auto-approve-readonly`](auto-approve-readonly.sh) ([catalog](../../docs/hooks.md#prompt)) — Auto-approves `Read`, `Glob`, `Grep`, `LS`, `WebSearch`, `WebFetch` so exploration doesn't block on confirmations.
- [`banned-words-enforcer`](banned-words-enforcer.sh) ([catalog](../../docs/hooks.md#prompt)) — Reads `~/.claude/banned-words.txt` and reminds Claude not to use any matching word in its reply. Additive, never rewrites.
- [`no-ask-human-blocker`](no-ask-human-blocker.sh) ([catalog](../../docs/hooks.md#prompt)) — When the user says "don't ask"/"just do it", appends an instruction reinforcing that Claude should not pause to clarify.
- [`rate-limiter`](rate-limiter.sh) ([catalog](../../docs/hooks.md#prompt)) — Tracks per-session tool-call frequency; warns Claude via context if it exceeds 50 calls in 60 seconds. Advisory only.

## Install just this category

```bash
bash scripts/install.sh --category=prompt --global
```

No profile maps directly to this category. `auto-approve-readonly` is the most commonly cherry-picked hook here; the others are situational.
