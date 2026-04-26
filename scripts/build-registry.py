#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""
Walk hooks/ and emit a structured registry: hooks.registry.yaml.

The registry is the single source of truth for the README hook tables,
docs/hooks.md, docs/events.md, the compatibility matrix, and the
--profile lookup in scripts/install.sh.

Run from the repo root:
    python3 scripts/build-registry.py
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HOOKS = REPO / "hooks"

EVENT_RE = re.compile(
    r"^# Event:\s+(\S+)(?:\s+\(matcher:\s*\"([^\"]+)\"\))?", re.MULTILINE
)
NAME_RE = re.compile(r"^# Hook name:\s+(\S+)", re.MULTILINE)
DESC_RE = re.compile(
    r"^# Description:\s+(.+?)(?=^# (?:Config|Install|$)|^[^#])",
    re.MULTILINE | re.DOTALL,
)
BYPASS_RE = re.compile(r"\bCLAUDE_[A-Z][A-Z0-9_]*", re.MULTILINE)


# Curated profile assignments. Values are tuples of (id, ...).
PROFILES = {
    "safe-default": [
        "audit-bash-commands",
        "audit-file-writes",
        "session-summary",
        "context-threshold-guard",
        "desktop-notify",
    ],
    "security": [
        "block-secrets",
        "protect-dotenv",
        "block-dangerous-bash",
        "block-system-paths",
        "scan-sql-injection",
        "check-npm-audit",
        "audit-bash-commands",
        "audit-file-writes",
    ],
    "quality": [
        "eslint-gate",
        "prettier-gate",
        "tsc-check",
        "validate-json-yaml",
        "python-lint",
        "dart-analyze",
        "go-vet",
        "test-coverage-check",
    ],
    "team": [
        "protect-main-branch",
        "validate-commit-message",
        "audit-file-writes",
        "session-summary",
        "conflict-detector",
        "stash-guard",
    ],
    "devops": [
        "terraform-destroy-guard",
        "kubernetes-prod-guard",
        "aws-prod-guard",
        "db-migration-guard",
        "docker-prod-guard",
        "github-actions-validator",
        "infra-audit-log",
    ],
    "solo-dev": [
        "auto-format-on-save",
        "ai-commit-message",
        "session-name-from-branch",
        "desktop-notify",
        "session-start-context",
    ],
    "notifications": [
        "desktop-notify",
        "macos-notify",
        "linux-notify",
        "slack-notify",
        "telegram-notify",
        "discord-notify",
        "pushover-notify",
        "sound-complete",
        "sound-error",
        "terminal-title",
    ],
    "ai-assisted": [
        "ai-code-review",
        "ai-security-scan",
        "ai-commit-message",
        "ai-pr-description",
        "ai-migration-safety",
    ],
}


def yaml_str(s: str) -> str:
    """Minimal YAML scalar quoting — enough for our descriptions."""
    if not s:
        return '""'
    if any(c in s for c in [':', '#', '"', "'", '\n']) or s != s.strip():
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'
    return s


def yaml_list(values: list[str], indent: int) -> str:
    if not values:
        return "[]"
    pad = " " * indent
    return "\n" + "\n".join(f"{pad}- {yaml_str(v)}" for v in values)


def detect_risk(text: str, blocks: bool) -> str:
    if blocks:
        return "blocking"
    if re.search(r"\bcurl\b|\bwget\b|api\.anthropic\.com|api\.openai\.com|hooks\.slack\.com", text):
        return "networked"
    if re.search(r"\b(kubectl|aws|terraform|gcloud|helm|docker)\b", text):
        # Logging-only privileged hooks (audit-bash) still have these
        # tokens in their grep patterns. Distinguish by whether the hook
        # actually invokes them vs just matches them in input.
        if re.search(r"^\s*(kubectl|aws|terraform|gcloud|helm|docker)\b", text, re.MULTILINE):
            return "privileged"
    if re.search(r"additionalContext|jq -n.*additionalContext", text):
        return "contextual"
    if re.search(r"\b(>\s*[\$~/]|tee\s+|append|>>)", text):
        return "modifying"
    return "passive"


def has_test(category: str, name: str) -> str | None:
    p = REPO / "tests" / category / f"{name}.bats"
    if p.exists():
        return str(p.relative_to(REPO))
    return None


def hook_has_network(text: str) -> bool:
    return bool(re.search(
        r"\bcurl\b|\bwget\b|api\.anthropic\.com|api\.openai\.com|hooks\.slack\.com|api\.telegram\.org|discord\.com/api|pushover\.net",
        text
    ))


def hook_writes_files(text: str) -> bool:
    # Heuristic: redirects out of stderr into a tracked file, or `tee`,
    # or `cp` / `mv` into ~/.claude/.
    if re.search(r"~/\.claude/[^/\s]+\.(log|md|json)", text):
        return True
    if re.search(r"\btee\b", text):
        return True
    return False


def hook_blocks(text: str) -> bool:
    return ("permissionDecision" in text and '"deny"' in text) or '"decision":"block"' in text


def hook_platforms(text: str) -> list[str]:
    text_lc = text.lower()
    plats = []
    if "darwin" in text_lc or "osascript" in text_lc or "macos" in text_lc:
        plats.append("macos")
    if "notify-send" in text_lc or "linux" in text_lc:
        plats.append("linux")
    if "wsl" in text_lc or "powershell.exe" in text_lc:
        plats.append("wsl")
    return plats or ["macos", "linux", "wsl"]


def main() -> int:
    rows = []
    seen_ids: set[str] = set()
    for path in sorted(HOOKS.rglob("*.sh")):
        if "/_lib/" in str(path):
            continue
        rel = path.relative_to(REPO)
        category = path.parent.name
        text = path.read_text()

        m_name = NAME_RE.search(text)
        m_event = EVENT_RE.search(text)
        m_desc = DESC_RE.search(text)
        if not (m_name and m_event):
            print(f"skip (incomplete header): {rel}", file=sys.stderr)
            continue
        name = m_name.group(1)
        if name in seen_ids:
            print(f"duplicate id: {name} ({rel})", file=sys.stderr)
        seen_ids.add(name)

        event = m_event.group(1)
        matcher = m_event.group(2) or ""

        desc = ""
        if m_desc:
            desc = re.sub(r"\s+", " ", m_desc.group(1)).strip()
            desc = re.sub(r"^# ?", "", desc)
            desc = re.sub(r" #$", "", desc).strip()
            desc = re.sub(r"\s+#\s+", " ", desc)

        bypass = sorted(set(BYPASS_RE.findall(text)) - {"CLAUDE_PLUGIN_ROOT"})
        blocks = hook_blocks(text)
        risk = detect_risk(text, blocks)

        rows.append({
            "id": name,
            "name": name.replace("-", " ").title().replace(" ", " "),
            "category": category,
            "path": str(rel),
            "event": event,
            "matcher": matcher,
            "description": desc,
            "risk_level": risk,
            "platforms": hook_platforms(text),
            "blocks_actions": blocks,
            "writes_files": hook_writes_files(text),
            "network_access": hook_has_network(text),
            "bypass_env": bypass,
            "tests": has_test(category, name),
            "profiles": [p for p, ids in PROFILES.items() if name in ids],
        })

    # Emit YAML by hand to avoid a PyYAML dependency.
    out = REPO / "hooks.registry.yaml"
    lines = [
        "# Single source of truth for the hook catalog.",
        "# Generated by scripts/build-registry.py — do not edit by hand.",
        "#",
        "# Re-run after adding / removing / renaming any hook:",
        "#   python3 scripts/build-registry.py",
        "",
        f"version: 1",
        f"hook_count: {len(rows)}",
        "",
        "profiles:",
    ]
    for prof, ids in PROFILES.items():
        lines.append(f"  {prof}:{yaml_list([h for h in ids if h in seen_ids], 4)}")
    lines.append("")
    lines.append("hooks:")
    for r in rows:
        lines.append(f"  - id: {yaml_str(r['id'])}")
        lines.append(f"    category: {yaml_str(r['category'])}")
        lines.append(f"    path: {yaml_str(r['path'])}")
        lines.append(f"    event: {yaml_str(r['event'])}")
        lines.append(f"    matcher: {yaml_str(r['matcher'])}")
        lines.append(f"    description: {yaml_str(r['description'])}")
        lines.append(f"    risk_level: {yaml_str(r['risk_level'])}")
        lines.append(f"    platforms:{yaml_list(r['platforms'], 6)}")
        lines.append(f"    blocks_actions: {str(r['blocks_actions']).lower()}")
        lines.append(f"    writes_files: {str(r['writes_files']).lower()}")
        lines.append(f"    network_access: {str(r['network_access']).lower()}")
        lines.append(f"    bypass_env:{yaml_list(r['bypass_env'], 6)}")
        lines.append(f"    profiles:{yaml_list(r['profiles'], 6)}")
        if r['tests']:
            lines.append(f"    tests: {yaml_str(r['tests'])}")
        else:
            lines.append("    tests: null")
        lines.append("")
    out.write_text("\n".join(lines).rstrip() + "\n")
    print(f"wrote {out.relative_to(REPO)} — {len(rows)} hooks")

    # Also emit a JSON twin for tooling (install.sh, doc renderers in jq, etc.)
    import json
    json_out = REPO / "hooks.registry.json"
    json_out.write_text(json.dumps({
        "version": 1,
        "hook_count": len(rows),
        "profiles": PROFILES,
        "hooks": rows,
    }, indent=2) + "\n")
    print(f"wrote {json_out.relative_to(REPO)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
