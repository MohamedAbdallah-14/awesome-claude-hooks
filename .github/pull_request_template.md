# Summary

What this PR changes, in one or two sentences.

# Hook contract checklist

If this PR adds or modifies a hook, confirm each item:

- [ ] Header has shebang, SPDX line, `Hook name`, `Event`, `Description`, and a JSON-valid `Install` snippet.
- [ ] `set -euo pipefail` is present.
- [ ] Reads stdin via `jq` and exits `0` on no-op.
- [ ] If the hook can block, it returns exit `2` with `{"decision":"block","reason":"..."}` and has a `CLAUDE_*` bypass env var.
- [ ] `bash scripts/lint-hooks.sh` passes locally.
- [ ] `shellcheck -S warning` is clean.
- [ ] If under `hooks/security/`, `hooks/quality/`, or `hooks/git/`: a `.bats` test exists in `tests/<category>/`.

# How this was tested

Commands run, payloads used, what passed.
