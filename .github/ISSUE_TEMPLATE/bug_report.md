---
name: Bug report
about: A hook misbehaves, a script breaks, or the docs lie
labels: bug
---

**Hook**: e.g. `hooks/security/block-secrets.sh`

**What happened**
A short description. Include the exact command or settings.json snippet that triggered it.

**Expected**
What you thought should happen.

**Actual**
What actually happened. Paste the exit code and any output.

**Environment**
- OS:
- bash version (`bash --version | head -1`):
- Claude Code version (`claude --version`):
- jq version (`jq --version`):

**Reproduction**
A minimal payload that reproduces the issue. Use `pretool_payload` from `tests/test_helper.bash` if useful.
