# Demo recording

`assets/demo.gif` is rendered from `demo/demo.cast`, which is recorded by
running `demo/demo.sh` under asciinema.

## Regenerate

```bash
brew install asciinema agg          # macOS
sudo apt-get install asciinema agg  # Debian/Ubuntu (if packaged)

# Re-record the cast (headless mode is fine for CI / scripted demos)
asciinema rec --overwrite \
  --command 'bash demo/demo.sh' \
  --rows 28 --cols 100 --idle-time-limit 1 \
  demo/demo.cast

# Render to GIF
agg --cols 100 --rows 28 --speed 1.5 --font-size 14 \
  demo/demo.cast assets/demo.gif
```

The `make demo` target runs both steps in sequence.

## What it shows

1. `bash scripts/install.sh --profile=security --dry-run --global` — preview
   of which hooks the security profile would wire into `~/.claude/settings.json`.
2. A synthetic `Write` tool call against `.env` is piped to `protect-dotenv.sh`,
   which emits a `permissionDecision: "deny"` JSON response.
3. A synthetic `Write` against `src/app.ts` is piped through the same hook
   and produces no output (allowed).

The demo doesn't talk to the Anthropic API and doesn't write any files. It's
purely a faithful re-creation of how Claude Code would invoke the hook.
