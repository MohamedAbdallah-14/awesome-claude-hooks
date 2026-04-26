---
name: Propose a new hook
about: Suggest a hook that would belong in this collection
labels: new-hook
---

**Hook name** (kebab-case): e.g. `block-aws-billing-spike`

**Category**: one of `ai`, `automation`, `context`, `cost`, `devops`, `fun`, `git`, `notifications`, `prompt`, `quality`, `security`, `session`.

**Event**: `PreToolUse`, `PostToolUse`, `Stop`, `SessionStart`, etc.

**What it does** — one paragraph.

**Why it belongs here** — what problem does it solve that the existing hooks don't?

**Bypass** — should it have a `CLAUDE_*` env var to disable it? If yes, propose the name.

**Tests** — would a `.bats` test be straightforward to write? (If it touches the network, we'll probably skip CI tests.)
