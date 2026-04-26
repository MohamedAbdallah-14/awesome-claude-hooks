# Security policy

These hooks run with full shell access on contributors' machines. Bugs in them can leak secrets, corrupt files, or block legitimate work. Report security issues privately so we can fix them before they're public.

## Reporting a vulnerability

**Do not open a public issue** for security problems.

Use one of:

- GitHub's private vulnerability reporting: https://github.com/MohamedAbdallah-14/awesome-claude-hooks/security/advisories/new
- Email the maintainer (address is in the repo owner's GitHub profile).

Include:
- Affected hook(s) and version (commit SHA or release tag).
- A minimal payload or command that reproduces the problem.
- The impact (data leak, command injection, denial of service, false negative on a security guard, etc.).

You should get an acknowledgment within 7 days. Critical issues get patched on the default branch and a fix release goes out within 14 days.

## Scope

In scope:

- Command injection in any hook.
- Hooks that fail to block what their description claims (security/quality category misses).
- Path traversal or secret-disclosure bugs in any script.
- Vulnerabilities in `scripts/install.sh` or other tooling.

Out of scope:

- Performance issues that don't have a security impact.
- Bugs in third-party tools the hooks invoke (`jq`, `notify-send`, etc.) — file those upstream.
- Issues that require an attacker who already has shell access on the user's machine (the hooks themselves run with that level of trust).

## Defense-in-depth notes for users

- Pin to a specific commit or release tag in your `settings.json` rather than tracking `main`. Review diffs before bumping.
- Run hooks from a clone you control, not directly from `curl | bash`.
- Hooks like `block-secrets` and `block-dangerous-bash` are best-effort guardrails. They reduce mistakes; they don't replace code review or proper secrets management.
