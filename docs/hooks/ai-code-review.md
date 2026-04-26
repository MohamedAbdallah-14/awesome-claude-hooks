# `ai-code-review`

> Source: [`hooks/ai/ai-code-review.sh`](../../hooks/ai/ai-code-review.sh)
> Event: `PostToolUse` (matcher `Write`)
> Risk level: `non-blocking` (injects context only)
> Bypass: unset `ANTHROPIC_API_KEY`, or remove the hook

## Problem

Claude writes a file. Claude moves on. The off-by-one in the new pagination loop, the missing escape on the SQL builder, the swapped error branches — none of it gets a second pair of eyes until a human reads the diff hours later. By then Claude has built three more files on top of the broken one.

This hook hands every freshly written file to Claude Haiku for a 2-sentence review and feeds the response back into the conversation as context. Bugs surface inside the same turn that wrote them.

## What it does

After every `Write`, sends the file content to Haiku with a tightly scoped prompt: flag only security vulnerabilities, off-by-one errors, or obvious bugs. If the file is clean, Haiku returns `LGTM` and the hook stays silent. If something looks wrong, the review is injected as `additionalContext` so the parent Claude session sees it on the next turn.

Filters before calling the API:

| Filter | Behavior |
|--------|----------|
| Extension not in `sh js ts py go dart rb rs` | Skipped silently |
| File over 100 lines | Skipped (cost + signal-to-noise) |
| `ANTHROPIC_API_KEY` unset | Skipped silently |
| `jq` or `curl` missing | Skipped silently |

## Before

Claude writes a paginated query helper with `page * size` instead of `(page - 1) * size`. The Write succeeds. Claude wires the helper into the next route. The bug is now two files deep.

## After

The PostToolUse hook fires. Haiku reads the file, spots the off-by-one, and the parent session receives:

```json
{
  "additionalContext": "AI code review (pagination.ts): Off-by-one in offset calculation — `page * size` skips the first page entirely; should be `(page - 1) * size`. Otherwise no security or correctness concerns."
}
```

Claude reads the context on the next turn and patches the helper before threading it through the rest of the codebase.

## Install

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/ai/ai-code-review.sh"
          }
        ]
      }
    ]
  }
}
```

`ANTHROPIC_API_KEY` must be exported in the environment Claude Code launches with.

## Test locally

```bash
export ANTHROPIC_API_KEY=sk-ant-...
echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"path":"/tmp/x.py","content":"def page(n,s): return n*s  # off by one"}}' \
  | bash hooks/ai/ai-code-review.sh; echo "exit: $?"
```

Expected: exit `0`, stdout JSON with `additionalContext` mentioning the off-by-one. With `ANTHROPIC_API_KEY` unset, expected: exit `0`, no stdout.

## Bypass

There's no env-var bypass — the hook is non-blocking by design. To disable for a session, unset `ANTHROPIC_API_KEY`. To disable permanently, remove the hook entry from `settings.json`.

## Safety notes

- **Network**: every matching write fires one POST to `https://api.anthropic.com/v1/messages`. The full file content (up to 100 lines) leaves your machine. Do not enable this hook on repos with proprietary code you can't send to Anthropic.
- **Cost**: roughly $0.001 per call against `claude-haiku-4-5` at the documented prompt size. A heavy editing session of 200 writes is ~$0.20.
- **Rate limits**: Haiku rate limits apply to your key. If the API returns 429, `curl -sf` swallows it and the hook exits 0 — you'll lose reviews for the rate-limited window but won't see errors.
- **Graceful degradation**: missing key, missing tools, malformed response, or a `LGTM` reply all result in silent exit 0. The hook never blocks Claude.
- The review is advisory. Haiku has no project context, no type information, no test results. Treat findings as a prompt to look, not as ground truth.
