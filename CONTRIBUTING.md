# Contributing to awesome-claude-hooks

## TL;DR

```bash
make install-deps   # shellcheck, bats-core, jq
make all            # shellcheck + hook contract lint + bats
```

If `make all` is green, your PR will pass CI on Ubuntu and macOS.

The full contract every hook must follow lives in [docs/hook-contract.md](docs/hook-contract.md). Read it before adding a hook — `scripts/lint-hooks.sh` enforces every rule in there.

## Before you open a PR

Scan the existing hooks and the category READMEs. If something close to your idea already exists, extend it or open an issue to discuss. Duplicate hooks with slightly different env vars are not useful.

---

## Adding a new hook

### 1. Pick the right category

| Category | What belongs here |
|---|---|
| `notifications/` | Alerting humans — desktop, mobile, chat |
| `security/` | Block, warn, or audit for risk |
| `context/` | Inject information into Claude's context window |
| `quality/` | Static analysis, linting, formatting gates |
| `automation/` | Side-effects triggered on tool use or session end |
| `git/` | Git workflow enforcement and automation |
| `cost/` | Usage tracking and budget controls |
| `fun/` | Low-stakes, clearly optional hooks |

If your hook doesn't fit any category cleanly, open an issue first and propose a new one. Don't invent a category unilaterally.

### 2. Use the template

The canonical template is in `docs/writing-your-own.md`. Copy it verbatim and fill in each section. The header comment block is not optional — it's what the installer reads to generate `settings.json` snippets.

Required header fields:

```bash
# Hook name:   kebab-case-name
# Event:       Stop  |  PreToolUse (matcher: "Bash")  |  PostToolUse (matcher: "Write|Edit|MultiEdit")
# Description: One sentence. What does this hook do when triggered?
#
# Config (env vars):
#   VAR_NAME   What it controls. Default if omitted.
#
# Install — add to ~/.claude/settings.json (or project .claude/settings.json):
#
#   {
#     "hooks": {
#       "Stop": [
#         { "matcher": "", "hooks": [{ "type": "command", "command": "/abs/path/hook.sh" }] }
#       ]
#     }
#   }
```

The `Install` block must show a minimal, copy-paste-ready `settings.json` snippet. Use `/abs/path/` as the placeholder path.

### 3. Required behavior

**Handle missing `jq` gracefully.** If your hook needs jq and it's absent, print a warning to stderr and `exit 0`. Never crash with an unhandled error.

```bash
if ! command -v jq &>/dev/null; then
  echo "[your-hook] WARNING: jq not found — install it with: brew install jq" >&2
  exit 0
fi
```

**Handle any missing optional dependency the same way.** `osascript`, `notify-send`, `curl`, `node` — if it's missing, degrade gracefully.

**Never leave Claude stuck.** Any unexpected condition — malformed stdin, missing file, network timeout — must result in `exit 0`. The only intentional non-zero exits are `exit 2` (block a tool call, PreToolUse only) with a JSON `{"decision":"block","reason":"..."}` body.

**PreToolUse hooks that block must emit the JSON decision object:**

```bash
jq -n --arg reason "Why this is blocked." '{"decision":"block","reason":$reason}'
exit 2
```

**Timeouts.** If your hook does anything slow (network, subprocess), use `timeout` or run async. PreToolUse hooks block Claude from proceeding — keep them under 2 seconds on the happy path.

### 4. Naming convention

- File name: `kebab-case.sh`, descriptive but concise.
- Prefer verb-noun: `block-secrets.sh`, `inject-git-context.sh`, `validate-commit-message.sh`.
- Avoid generic names: `hook.sh`, `my-hook.sh`, `helper.sh`.

### 5. Make it executable

```bash
chmod +x hooks/category/your-hook.sh
```

Commit with the executable bit set. The installer relies on this.

### 6. Test it before opening a PR

Test with real payloads piped to stdin. Examples for each event type:

```bash
# Stop hook
echo '{"hook_event_name":"Stop","session_id":"test123","transcript_path":"/tmp/test","stop_hook_active":true}' \
  | bash hooks/notifications/macos-notify.sh

# PreToolUse hook — general
echo '{"hook_event_name":"PreToolUse","session_id":"test123","transcript_path":"/tmp/test","tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | bash hooks/security/block-dangerous-bash.sh; echo "Exit: $?"

# PreToolUse hook — Write with secrets
echo '{"hook_event_name":"PreToolUse","session_id":"test123","transcript_path":"/tmp/test","tool_name":"Write","tool_input":{"file_path":"/tmp/test.ts","content":"const key = \"sk-abc123def456ghi789jkl012mno345pqr678stu901\""}}' \
  | bash hooks/security/block-secrets.sh; echo "Exit: $?"

# PostToolUse hook
echo '{"hook_event_name":"PostToolUse","session_id":"test123","transcript_path":"/tmp/test","tool_name":"Write","tool_input":{"file_path":"/tmp/foo.ts"},"tool_response":{"output":""}}' \
  | bash hooks/quality/tsc-check.sh
```

Include the test command and its output in your PR description.

### 7. Update the docs

- Add a row to `hooks/<category>/README.md`.
- Add a row to the main `README.md` index table.

Both tables have the same columns: Hook, Event, Description, Config vars.

---

## PR requirements

- **Tested.** Show test command and output in the PR description. No exceptions.
- **Dependency-safe.** Missing `jq`, missing optional tools — hook exits 0 with a warning. Never a stack trace.
- **Cross-platform.** Must work on macOS and Linux, or must clearly document the platform limitation in the header comment. Platform-specific hooks (e.g., `macos-notify.sh`) are fine — they just need to `exit 0` gracefully on unsupported platforms.
- **No network calls in PreToolUse hooks.** These are blocking. A DNS timeout or a flaky API will stall Claude. If you need a network call, do it PostToolUse or Stop, and run it in the background if the result isn't needed synchronously.
- **Config via environment variables only.** No flags, no config files. Document every env var in the header comment.
- **One hook per file.** Don't combine two unrelated behaviors into a single script.

---

## Hook quality bar

Every hook in this repo must pass:

**Real use case.** There must be a genuine workflow problem this solves. "Shows a notification" or "logs tool calls" are real. "Prints hello" is not.

**Specific.** Does one thing well. A hook that does notifications *and* logs *and* enforces linting is three hooks.

**Fast.** Under 2 seconds for PreToolUse hooks on a warm machine. Anything slower needs to be async (background subprocess, fire-and-forget).

**Safe.** Exits 0 on any unexpected condition. The rule: hooks must never make Claude worse than if the hook weren't installed. A hook that crashes and blocks a session is worse than no hook.

---

## Repo structure rules

- One hook per file.
- Category READMEs must be kept up to date with every new hook.
- No external dependencies beyond: `bash`, `jq`, standard POSIX tools, and optional platform tools (`osascript`, `notify-send`, `paplay`, etc.).
- No bundled binaries. No vendored node_modules. No Python packages.

---

## Local development tips

Clone and run directly — there's no build step:

```bash
git clone https://github.com/mohamedabdallah/awesome-claude-hooks
cd awesome-claude-hooks
chmod +x hooks/**/*.sh
bash scripts/install.sh
```

To iterate on a hook without reinstalling, just edit the file. Claude Code reads the hook command on every trigger — there's no cache to clear.

To run the installer in dry-run mode and see what would change:

```bash
bash scripts/install.sh --all --dry-run
```

To remove everything this repo installed from your settings:

```bash
bash scripts/uninstall.sh --dry-run  # preview
bash scripts/uninstall.sh            # apply
```
