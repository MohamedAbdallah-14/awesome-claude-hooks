# Go Starter Pack

Drop-in `settings.json` for Go services and binaries. Layers `safe-default` with `go vet` after every Go file edit, plus secret/dotenv/dangerous-bash blocks.

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands`.

**Pre-Edit/Write**
- `security/block-secrets` — file-write path.
- `quality/validate-json-yaml` — parse-check JSON/YAML (`.golangci.yml`, k8s manifests, etc.).

**Post-Edit/Write**
- `quality/go-vet` — runs `go vet ./...` after Go file changes; also flags unformatted files via `gofmt -l`.
- `security/audit-file-writes` — write log.

**Post-Bash**
- `context/inject-recent-commits`.

**UserPromptSubmit**
- `session/context-threshold-guard` — warns when transcript grows past a threshold.

**Stop**
- `notifications/desktop-notify`, `session/session-summary`, `context/inject-git-context`, `cost/log-tool-usage`.

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/go/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/go/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=quality --global
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- `go-vet.sh` needs the Go toolchain on `PATH`. There is no dedicated `golangci-lint` hook — run it from CI or pre-commit if you want stricter linting.
