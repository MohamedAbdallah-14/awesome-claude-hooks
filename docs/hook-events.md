# Hook Events Reference

Hooks fire on Claude Code lifecycle events. Each event delivers a JSON payload on stdin. Respond with JSON on stdout, exit with a meaningful exit code, or do both.

## Event Categories

### Session Events

- **SessionStart** — fires once at session beginning. Payload: `{session_id, cwd, hook_event_name}`. Use for: injecting project context, loading env vars via CLAUDE_ENV_FILE pattern.
- **SessionEnd** — fires when session terminates normally. Same payload. Use for: writing summaries, cleanup.
- **PreCompact** — fires before Claude compacts the conversation. Payload includes `transcript_path`. Use for: backing up conversation, injecting pre-compaction context.

### Tool Events

- **PreToolUse** — fires before ANY tool executes. Payload: `{tool_name, tool_input, session_id, cwd}`. Can block (exit 2) or rewrite input via `updatedInput`. Most powerful event.
- **PostToolUse** — fires after tool completes. Payload adds: `tool_response`. Cannot block (already ran). Use for: side effects, logging, analysis.

### User Events

- **UserPromptSubmit** — fires when user submits a message. Payload: `{prompt, session_id, cwd}`. Can rewrite via `hookSpecificOutput.updatedPrompt`. Use for: prepending context, enforcing rules.
- **PermissionRequest** — fires when Claude requests permission to use a tool. Payload: `{tool_name, tool_input}`. Can auto-approve/deny via `hookSpecificOutput.permissionDecision`.

### Agent Events

- **SubagentStart** — fires when a subagent is spawned. Payload: `{subagent_id, parent_session_id}`. Use for: logging, rate limiting.
- **SubagentStop** — fires when a subagent completes. Use for: aggregating results.

### Task Events

- **TaskCreated** — fires when a Task is created. Use for: logging, work tracking.

### Environment Events

- **CwdChanged** — fires when working directory changes. Payload includes new `cwd`. Use for: loading directory-specific config.
- **FileChanged** — fires when a file changes on disk (outside Claude's writes). Use for: reloading context.

### Collaboration Events

- **TeammateIdle** — fires when a teammate agent is idle. Use for: dispatching work.

---

## Payload Schema

Full payload with all possible fields:

```json
{
  "hook_event_name": "PreToolUse",
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/home/user/project",
  "tool_name": "Write",
  "tool_input": {
    "path": "/foo/bar.ts",
    "content": "..."
  },
  "tool_response": {
    "content": "...",
    "is_error": false
  },
  "prompt": "user message text"
}
```

Not all fields are present in every event. `tool_name` and `tool_input` appear only in tool events. `tool_response` appears only in PostToolUse. `prompt` appears only in UserPromptSubmit.

---

## Handler Types

### command (most common)

Runs a shell command. Stdin receives the JSON payload.

```json
{"type": "command", "command": "bash ~/.claude/hooks/security/block-secrets.sh"}
```

### http

POSTs the payload to a webhook URL.

```json
{"type": "http", "url": "https://hooks.example.com/claude", "method": "POST"}
```

### mcp_tool

Calls an MCP tool with the payload.

```json
{"type": "mcp_tool", "server": "my-server", "tool": "on_tool_use"}
```

### prompt

Sends the payload to Claude (as a mini LLM call) for a yes/no decision. Result determines block/allow.

```json
{"type": "prompt", "prompt": "Should this bash command be allowed? Reply YES or NO."}
```

### agent

Spawns a full subagent with the payload. Use for complex async processing.

```json
{"type": "agent", "prompt": "Analyze this code change and report issues."}
```

---

## Response Format

### Inject context (any event)

```json
{"additionalContext": "text Claude will see before its next response"}
```

### Block tool (PreToolUse only — exit code 2)

```bash
echo '{"decision":"block","reason":"Blocked: targets production"}'
exit 2
```

### Rewrite tool input (PreToolUse — updatedInput)

```json
{
  "hookSpecificOutput": {
    "updatedInput": {"command": "echo 'safe replacement'"}
  }
}
```

This silently rewrites the tool's input before execution. Useful for: normalizing paths, stripping dangerous flags, redirecting writes.

### Permission decision (PermissionRequest only)

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow",
    "updatedInput": {}
  }
}
```

Deny with a reason:

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "reason": "Production writes are not permitted in this session."
  }
}
```

### Modify user prompt (UserPromptSubmit only)

```json
{
  "hookSpecificOutput": {
    "updatedPrompt": "modified prompt text"
  }
}
```

---

## Special Features

### CLAUDE_ENV_FILE

On SessionStart, write a file path to the `CLAUDE_ENV_FILE` env var to inject persistent environment variables into all Bash tool executions in that session:

```bash
echo "DEPLOY_ENV=staging" > /tmp/claude-session-env.sh
echo "/tmp/claude-session-env.sh" > "$CLAUDE_ENV_FILE"
```

### asyncRewake

For long-running background hooks, set `asyncRewake: true` in the response to have Claude re-check after the hook completes:

```json
{"asyncRewake": true, "additionalContext": "Background scan started"}
```

### if field (conditional hooks)

The `if` field in a hook config evaluates a shell expression to decide whether the hook runs at all:

```json
{
  "type": "command",
  "command": "bash hook.sh",
  "if": "test -f .production"
}
```

### matcher field

For PreToolUse/PostToolUse, `matcher` is a regex applied to `tool_name`:

```json
{
  "matcher": "Write|Edit",
  "hooks": [...]
}
```

Empty matcher matches all tools.

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Allow / pass through |
| 1 | Error (logged, not blocking) |
| 2 | Block execution (PreToolUse only) |

---

## Settings.json Structure

Complete example wiring multiple events:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/security/block-secrets.sh"}
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/quality/validate-json-yaml.sh"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/cost/log-tool-usage.sh"}
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/notifications/macos-notify.sh"}
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/session/session-start-context.sh"}
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/prompt/auto-approve-readonly.sh"}
        ]
      }
    ]
  }
}
```
