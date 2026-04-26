# `validate-json-yaml`

> Source: [`hooks/quality/validate-json-yaml.sh`](../../hooks/quality/validate-json-yaml.sh)
> Event: `PreToolUse` (matcher `Write|Edit|MultiEdit`)
> Risk level: `blocking`
> Bypass: none — fix the syntax error instead

## Problem

A broken `package.json` silently disables every npm script. A malformed `docker-compose.yml` brings down a stack on the next deploy. A `.github/workflows/ci.yml` with a tab where a space should be is a green CI badge that quietly stopped running anything.

These mistakes are usually one comma. They're also catastrophic because tooling either crashes loudly later or, worse, succeeds silently. This hook catches the syntax error at write time, before it reaches disk.

## What it catches

| File pattern | Validator |
|--------------|-----------|
| `*.json` | `python3 -m json.tool` |
| `*.yaml`, `*.yml` | `python3 -c "import yaml; yaml.safe_load(...)"` |

If `python3` or `pyyaml` is missing, the hook prints a one-line warning to stderr and allows the write. Better to skip than lock the user out.

## Before

Claude wants to write:

```json
{
  "name": "myapp",
  "scripts": {
    "test": "jest",
  }
}
```

Trailing comma. JSON parsers reject it. npm sees a corrupt manifest. Without the hook, you find out next time CI runs.

## After

The Write is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: content for /repo/package.json is not valid JSON.\n\nParse error: Expecting property name enclosed in double quotes: line 5 column 3 (char 56)\n\nFix the JSON syntax before writing."
  }
}
```

Claude removes the trailing comma and re-issues the Write.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/quality/validate-json-yaml.sh"
          }
        ]
      }
    ]
  }
}
```

Or as part of the `quality` profile.

## Test locally

```bash
# Invalid JSON
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x.json","content":"{\"a\": 1,}"}}' \
  | bash hooks/quality/validate-json-yaml.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`, parse error in the reason.

Coverage: [`tests/quality/validate-json-yaml.bats`](../../tests/quality/validate-json-yaml.bats).

## Bypass

There is no env var. The hook is meant to be unbypassable — fix the syntax error instead. If you genuinely need to write malformed JSON for a test fixture, write it to a `.txt` first and rename, or extend the hook to skip files matching a pattern (and send a PR).

## Safety notes

- No network calls.
- Calls `python3` as a subprocess. If `python3` is on PATH, output is captured and only the parse error is surfaced — no environment variables, no other state.
- The hook reads the proposed file content from stdin's `tool_input.content`, not from disk. The on-disk file is untouched if the validation fails (because the Write never happens).
- File extensions outside `.json` / `.yaml` / `.yml` are allowed without checking. If you're validating a YAML file that lives at `kustomize/overlay/prod/secret`, rename the extension or extend the script.
