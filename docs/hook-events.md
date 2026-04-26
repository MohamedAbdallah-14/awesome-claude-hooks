# Hook Events Reference

This is the complete reference for all Claude Code hook events. Each section covers when the event fires, the exact JSON schema on stdin, what your hook can output, and a concrete example.

## Table of Contents

- [PreToolUse](#pretooluse)
- [PostToolUse](#posttooluse)
- [Stop](#stop)
- [SubagentStop](#subagentstop)
- [PreCompact](#precompact)
- [Output reference summary](#output-reference-summary)

---

## PreToolUse

**Fires:** Immediately before Claude executes any tool call — before Bash runs a command, before Write creates a file, before Edit modifies one. This is the primary control point for enforcement and context injection.

### Input JSON schema

```json
{
  "hook_event_name": "PreToolUse",
  "session_id": "string",
  "transcript_path": "string (absolute path to session transcript)",
  "tool_name": "string (e.g. Bash, Write, Edit, Read, WebSearch)",
  "tool_input": {
    // shape varies by tool — see below
  }
}
```

**`tool_input` shapes by tool:**

| Tool | Key fields |
|------|-----------|
| `Bash` | `{"command": "string"}` |
| `Write` | `{"file_path": "string", "content": "string"}` |
| `Edit` | `{"file_path": "string", "old_string": "string", "new_string": "string"}` |
| `Read` | `{"file_path": "string"}` |
| `MultiEdit` | `{"file_path": "string", "edits": [...]}` |
| `WebSearch` | `{"query": "string"}` |
| `WebFetch` | `{"url": "string"}` |
| `TodoWrite` | `{"todos": [...]}` |

### What your hook can do

**Block the tool call** — exit code 2, print JSON to stdout:

```json
{"decision": "block", "reason": "Reason shown to Claude explaining why it was blocked."}
```

Claude sees the reason and can adjust its approach.

**Approve with added context** — exit code 0, print JSON to stdout:

```json
{"decision": "approve", "context": "Additional context injected into Claude's view of this tool call."}
```

Use this when the tool call is fine but you want Claude to know something (e.g., "note: this file has 3 failing tests").

**Inject context only** — exit code 0, print JSON to stdout:

```json
{"context": "Any string. Claude sees this alongside the tool call."}
```

**Silent allow** — exit code 0, no output. The tool runs normally.

### Matcher

The `matcher` field in `settings.json` is a regex matched against `tool_name`. Examples:

```
"Bash"              → matches only Bash
"Write|Edit"        → matches Write or Edit
"Write|Edit|MultiEdit" → matches any file-writing tool
""                  → matches all tools (same as omitting matcher)
"^(Bash|Write)$"    → exact match for Bash or Write
```

### Full example: blocking dangerous commands

```json
// settings.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks-lib/hooks/security/bash-guard.sh"}]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# bash-guard.sh — block dangerous rm commands

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Block unconditional recursive deletes from root-adjacent paths
if echo "$COMMAND" | grep -qE 'rm\s+-[rf]+\s+/[^t]'; then
  echo '{"decision":"block","reason":"Blocked: recursive delete from a root-level path. Use a more specific path."}'
  exit 2
fi

exit 0
```

**Stdin example:**

```json
{
  "hook_event_name": "PreToolUse",
  "session_id": "abc-123",
  "transcript_path": "/Users/you/.claude/sessions/abc-123.jsonl",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /usr/local/myapp"
  }
}
```

---

## PostToolUse

**Fires:** After a tool call completes successfully. The hook receives the tool's output in addition to the input. This is the right place for linters, formatters, test runners, and audit logging.

### Input JSON schema

```json
{
  "hook_event_name": "PostToolUse",
  "session_id": "string",
  "transcript_path": "string",
  "tool_name": "string",
  "tool_input": {
    // same shape as PreToolUse tool_input
  },
  "tool_response": {
    // shape varies by tool — see below
  }
}
```

**`tool_response` shapes by tool:**

| Tool | Key fields |
|------|-----------|
| `Bash` | `{"output": "string (stdout+stderr)", "exit_code": number}` |
| `Write` | `{"success": true, "file_path": "string"}` |
| `Edit` | `{"success": true, "file_path": "string"}` |
| `Read` | `{"content": "string"}` |

### What your hook can do

PostToolUse cannot block (the tool already ran). You can:

- **Inject context for Claude's next step** — exit 0, print JSON:
  ```json
  {"context": "ESLint found 2 errors in the file you just wrote. See /tmp/eslint-out.txt"}
  ```
- **Run side effects** — lint, format, log, notify. Exit 0 silently.

### Full example: running ESLint after file edits

```json
// settings.json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks-lib/hooks/quality/eslint-gate.sh"}]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# eslint-gate.sh — run ESLint after file writes, inject results as context

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Only run on JS/TS files
if ! echo "$FILE" | grep -qE '\.(js|jsx|ts|tsx|mjs|cjs)$'; then
  exit 0
fi

if ! command -v eslint &>/dev/null; then
  exit 0
fi

OUTPUT=$(eslint --format compact "$FILE" 2>&1)
EXIT=$?

if [ $EXIT -ne 0 ]; then
  ESCAPED=$(echo "$OUTPUT" | head -20 | jq -Rs .)
  echo "{\"context\": \"ESLint output for $FILE:\\n$OUTPUT\"}"
fi

exit 0
```

**Stdin example:**

```json
{
  "hook_event_name": "PostToolUse",
  "session_id": "abc-123",
  "transcript_path": "/Users/you/.claude/sessions/abc-123.jsonl",
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/Users/you/project/src/index.ts",
    "content": "const x = require('fs')\n"
  },
  "tool_response": {
    "success": true,
    "file_path": "/Users/you/project/src/index.ts"
  }
}
```

---

## Stop

**Fires:** When Claude finishes its response and becomes idle — the main session agent has completed a turn.

This is the most common hook event. Use it for completion notifications, auto-commit, session summaries, and any "when Claude is done" action.

### Input JSON schema

```json
{
  "hook_event_name": "Stop",
  "session_id": "string",
  "transcript_path": "string (path to the full session transcript as JSONL)",
  "stop_hook_active": true
}
```

**`stop_hook_active`**: Always `true` for the Stop event on the main agent. Indicates this is not a subagent. If you need to differentiate between main agent and subagents, use `stop_hook_active` as the discriminator.

### What your hook can do

**Re-activate Claude (keep session going)** — exit code 2, print JSON to stdout:

```json
{"decision": "block", "reason": "Run git status and commit any staged changes before finishing."}
```

Claude will wake up, see your message as an instruction, and continue. Use this for enforcing "always commit" or "always run tests" workflows. Be careful — a hook that always blocks creates an infinite loop. Add a condition.

**Run side effects only** — exit 0. No output needed. This is the correct behavior for notifications.

### Full example: macOS desktop notification

```json
// settings.json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [{"type": "command", "command": "bash ~/.claude/hooks-lib/hooks/notifications/macos-notify.sh"}]
      }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# macos-notify.sh — desktop notification when Claude finishes

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"' | cut -c1-8)

osascript -e "display notification \"Session $SESSION complete\" with title \"Claude Code\" sound name \"Glass\"" 2>/dev/null

exit 0
```

**Stdin example:**

```json
{
  "hook_event_name": "Stop",
  "session_id": "abc-123-def-456",
  "transcript_path": "/Users/you/.claude/sessions/abc-123-def-456.jsonl",
  "stop_hook_active": true
}
```

---

## SubagentStop

**Fires:** When a spawned subagent finishes. Claude Code can run parallel subagents for certain tasks; each one fires SubagentStop when it completes.

### How it differs from Stop

| | Stop | SubagentStop |
|--|------|-------------|
| `hook_event_name` | `"Stop"` | `"SubagentStop"` |
| `stop_hook_active` | `true` | `false` |
| Agent type | Main session agent | Spawned subagent |
| Typical use | User-facing notifications | Internal completion tracking |

In practice, most hooks only need to handle `Stop`. Register under `SubagentStop` only if you're doing subagent-specific tracking (e.g., timing individual parallel tasks).

### Input JSON schema

```json
{
  "hook_event_name": "SubagentStop",
  "session_id": "string (same session_id as the parent)",
  "transcript_path": "string",
  "stop_hook_active": false
}
```

### What your hook can do

Same output semantics as `Stop`. Exit 2 with a JSON decision to re-activate the subagent. Exit 0 for side effects only.

### Full example: log subagent completions

```bash
#!/usr/bin/env bash
# log-subagent.sh — append subagent completion timestamps to a log

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) subagent-stop session=$SESSION" \
  >> ~/.claude/logs/subagent-completions.log

exit 0
```

**Stdin example:**

```json
{
  "hook_event_name": "SubagentStop",
  "session_id": "abc-123-def-456",
  "transcript_path": "/Users/you/.claude/sessions/abc-123-def-456.jsonl",
  "stop_hook_active": false
}
```

---

## PreCompact

**Fires:** Before Claude Code compacts the session context. Context compaction discards older conversation turns to stay within the context window. After compaction, earlier tool calls and their results are gone.

### Why this matters

If your hooks depend on session history (e.g., a summary hook that reads the transcript), PreCompact is your last chance to extract and save state before it's compressed. It's also the right place to write a checkpoint to a file that survives compaction.

### Input JSON schema

```json
{
  "hook_event_name": "PreCompact",
  "session_id": "string",
  "transcript_path": "string"
}
```

### What your hook can do

- **Save state before compaction** — read the transcript file at `transcript_path` and extract anything you need to persist.
- **Inject a summary as context** — exit 0, print JSON:
  ```json
  {"context": "Before compaction: 3 files modified (index.ts, auth.ts, schema.sql), all tests passing."}
  ```
  Claude will carry this context forward through the compaction.
- **Silent side effect** — exit 0, no output.

PreCompact cannot block compaction.

### Full example: save a checkpoint before compaction

```bash
#!/usr/bin/env bash
# pre-compact-checkpoint.sh — write a state summary before context is compressed

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')

CHECKPOINT_DIR=~/.claude/checkpoints
mkdir -p "$CHECKPOINT_DIR"

# Extract the last 10 tool calls from the transcript and save them
if [ -f "$TRANSCRIPT" ]; then
  grep '"tool_name"' "$TRANSCRIPT" | tail -20 \
    > "$CHECKPOINT_DIR/$SESSION-pre-compact.txt" 2>/dev/null
fi

# Inject a summary Claude can use after compaction
MODIFIED_FILES=$(grep -o '"file_path":"[^"]*"' "$TRANSCRIPT" 2>/dev/null \
  | sort -u | sed 's/"file_path":"//;s/"//' | head -10 | tr '\n' ', ')

if [ -n "$MODIFIED_FILES" ]; then
  echo "{\"context\": \"Pre-compaction checkpoint: files touched in this session: $MODIFIED_FILES\"}"
fi

exit 0
```

**Stdin example:**

```json
{
  "hook_event_name": "PreCompact",
  "session_id": "abc-123-def-456",
  "transcript_path": "/Users/you/.claude/sessions/abc-123-def-456.jsonl"
}
```

---

## Output Reference Summary

| Output type | Stdout | Exit code | Works in |
|-------------|--------|-----------|----------|
| Silent allow | (none) | 0 | All events |
| Context injection | `{"context": "..."}` | 0 | All events |
| Approve with context | `{"decision":"approve","context":"..."}` | 0 | PreToolUse |
| Block tool call | `{"decision":"block","reason":"..."}` | 2 | PreToolUse |
| Re-activate Claude | `{"decision":"block","reason":"..."}` | 2 | Stop, SubagentStop |
| Error (treated as allow) | anything | 1 or other | All events |

**Key rules:**
- stdout is for JSON responses only. Debug output goes to stderr.
- Exit code 2 is the block signal. Any other non-zero exit is treated as allow in most contexts.
- `"reason"` in a block decision is shown to Claude, not the user. Write it as an instruction.
- `"context"` in any response is injected into Claude's view of the current turn.
