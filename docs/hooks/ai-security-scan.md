# `ai-security-scan`

> Source: [`hooks/ai/ai-security-scan.sh`](../../hooks/ai/ai-security-scan.sh)
> Event: `PostToolUse` (matcher `Write`)
> Risk level: `non-blocking` (injects context only)
> Bypass: `CLAUDE_SKIP_AI_SECURITY=1`

## Problem

Pattern-based secret scanners catch hardcoded keys but miss the harder OWASP-shaped bugs: a SQL string built with concatenation, a shell-spawning call fed user input, a JWT verified with `none`, a path joined without normalization. These ship past `block-secrets` without a peep because they aren't *strings* — they're *shapes*.

This hook sends every freshly written `.py/.js/.ts/.go` file to Haiku with a tight OWASP Top 10 prompt and surfaces the findings as conversation context. It's a second-opinion scan that thinks in vulnerability classes, not regexes.

## What it does

After every `Write` of a Python/JS/TS/Go file, trims the content to the first 50 lines and asks Haiku to flag OWASP Top 10 issues. If clean, Haiku returns `CLEAN` and the hook stays silent. If issues are found, they're injected as `additionalContext` in the format `VULN_TYPE: line_hint`.

Filters before calling the API:

| Filter | Behavior |
|--------|----------|
| Extension not in `py js ts go` | Skipped silently |
| `CLAUDE_SKIP_AI_SECURITY=1` | Skipped silently |
| `ANTHROPIC_API_KEY` unset | Skipped silently |
| `jq` or `curl` missing | Skipped silently |

The 50-line cap exists for cost and signal density. Most OWASP smells live in the import block and the first request handler — past line 50, false-positive rate climbs faster than detection rate.

## Before

Claude writes a search endpoint that builds a query by concatenating `req.query.name` directly into raw SQL. The file passes the linter. It passes `block-secrets` (no hardcoded keys). The injection bug ships into the next file Claude builds on top of it.

## After

The PostToolUse hook fires. Haiku spots the concatenation and the parent session receives:

```json
{
  "additionalContext": "Security scan (search.ts): SQL_INJECTION: line 12 — req.query.name concatenated into raw SQL. Use parameterized query."
}
```

Claude reads the finding and switches to a parameterized query before the bug propagates.

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
            "command": "/abs/path/to/hooks/ai/ai-security-scan.sh"
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
echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"path":"/tmp/x.js","content":"db.query(\"SELECT * FROM u WHERE id=\" + req.query.id)"}}' \
  | bash hooks/ai/ai-security-scan.sh; echo "exit: $?"
```

Expected: exit `0`, stdout JSON with `additionalContext` flagging SQL injection. With `CLAUDE_SKIP_AI_SECURITY=1`, expected: exit `0`, no stdout.

## Bypass

`CLAUDE_SKIP_AI_SECURITY=1` disables the hook for the session. Use it when working on test fixtures with deliberate-looking vulnerabilities, or in offline mode. Unset it when you're back on real code.

To disable permanently, unset `ANTHROPIC_API_KEY` or remove the hook entry from `settings.json`.

## Safety notes

- **Network**: every matching write sends the first 50 lines to `https://api.anthropic.com/v1/messages`. Source code leaves your machine. Don't enable on repos with proprietary code you can't send to Anthropic.
- **Cost**: roughly $0.001 per call against `claude-haiku-4-5`. A 50-line trim keeps tokens predictable. A heavy session of 100 writes is ~$0.10.
- **Rate limits**: Haiku rate limits apply to your key. 429s are swallowed by `curl -sf` and the hook exits 0.
- **Graceful degradation**: missing key, missing tools, malformed response, or a `CLEAN` reply all result in silent exit 0. The hook never blocks.
- **Coverage**: 50-line trim means vulnerabilities past line 50 are invisible to this hook. Pair with a real SAST tool (Semgrep, CodeQL) for full-file coverage. This hook is a fast first-pass, not a substitute.
- Findings are advisory and based on a partial view. Verify before acting.
