#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""
Read hooks.registry.yaml and render:

  docs/hooks.md            — full catalog grouped by category
  docs/events.md           — same hooks regrouped by event name
  docs/compatibility.md    — operational matrix (blocks/network/writes/platforms)

Run from the repo root:
    python3 scripts/render-docs.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REGISTRY_PATH = REPO / "hooks.registry.yaml"


# Tiny YAML reader good enough for the registry shape we generate.
def load_registry() -> dict:
    text = REGISTRY_PATH.read_text()
    out: dict = {"profiles": {}, "hooks": []}
    cur_section = None
    cur_hook: dict | None = None
    cur_profile = None
    cur_list_field = None  # within a hook
    list_indent = None

    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.strip()

        if indent == 0:
            cur_section = None
            cur_hook = None
            cur_profile = None
            cur_list_field = None
            if line.startswith("hooks:"):
                cur_section = "hooks"
                continue
            if line.startswith("profiles:"):
                cur_section = "profiles"
                continue
            m = re.match(r"^(\w+):\s*(.+)$", line)
            if m:
                out[m.group(1)] = _parse_scalar(m.group(2))
            continue

        if cur_section == "profiles":
            if indent == 2 and line.endswith(":"):
                cur_profile = line[:-1]
                out["profiles"][cur_profile] = []
                continue
            if indent >= 4 and line.startswith("- ") and cur_profile:
                out["profiles"][cur_profile].append(_unquote(line[2:]))
                continue

        if cur_section == "hooks":
            if indent == 2 and line.startswith("- id:"):
                if cur_hook is not None:
                    out["hooks"].append(cur_hook)
                cur_hook = {"id": _unquote(line[len("- id:"):].strip())}
                cur_list_field = None
                continue
            if cur_hook is None:
                continue
            if indent == 4:
                # Either "key: value" or "key:" (empty / list-prefix)
                m = re.match(r"^(\w+):\s*(.*)$", line)
                if not m:
                    continue
                key, val = m.group(1), m.group(2)
                if val == "" or val == "null":
                    cur_hook[key] = [] if key in {"platforms", "bypass_env", "profiles"} else None
                    cur_list_field = key if key in {"platforms", "bypass_env", "profiles"} else None
                elif val == "[]":
                    cur_hook[key] = []
                    cur_list_field = None
                else:
                    cur_hook[key] = _parse_scalar(val)
                    cur_list_field = None
                continue
            if indent >= 6 and line.startswith("- ") and cur_list_field:
                cur_hook[cur_list_field].append(_unquote(line[2:]))

    if cur_hook is not None and cur_section == "hooks":
        out["hooks"].append(cur_hook)
    return out


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    return s


def _parse_scalar(s: str):
    s = s.strip()
    if s in {"true", "false"}:
        return s == "true"
    if s == "null":
        return None
    if re.match(r"^-?\d+$", s):
        return int(s)
    return _unquote(s)


def fmt_event(h: dict) -> str:
    if h.get("matcher"):
        return f"`{h['event']}` (`{h['matcher']}`)"
    return f"`{h['event']}`"


def fmt_yes_no(b) -> str:
    return "✅" if b else "—"


def fmt_platforms(plats: list[str]) -> str:
    return ", ".join(plats) if plats else "all"


def render_hooks_md(reg: dict) -> str:
    by_cat: dict[str, list[dict]] = {}
    for h in reg["hooks"]:
        by_cat.setdefault(h["category"], []).append(h)
    lines = [
        "# Hook catalog",
        "",
        "Generated from `hooks.registry.yaml` by `scripts/render-docs.py`.",
        "Re-run after registry changes; do not edit by hand.",
        "",
        f"**{reg['hook_count']} hooks** across {len(by_cat)} categories.",
        "",
    ]
    for cat in sorted(by_cat):
        lines.append(f"## {cat}")
        lines.append("")
        lines.append("| Hook | Event | Risk | Description |")
        lines.append("|------|-------|------|-------------|")
        for h in sorted(by_cat[cat], key=lambda x: x["id"]):
            lines.append(
                f"| [`{h['id']}`]({h['path']}) | {fmt_event(h)} | "
                f"`{h['risk_level']}` | {h['description'] or '_no description_'} |"
            )
        lines.append("")
    return "\n".join(lines)


def render_events_md(reg: dict) -> str:
    by_event: dict[str, list[dict]] = {}
    for h in reg["hooks"]:
        by_event.setdefault(h["event"], []).append(h)
    lines = [
        "# Hooks by event",
        "",
        "Generated from `hooks.registry.yaml` by `scripts/render-docs.py`.",
        "",
    ]
    for ev in sorted(by_event):
        lines.append(f"## `{ev}` ({len(by_event[ev])})")
        lines.append("")
        for h in sorted(by_event[ev], key=lambda x: x["id"]):
            matcher = f" matcher `{h['matcher']}`" if h.get("matcher") else ""
            lines.append(
                f"- [`{h['id']}`]({h['path']}){matcher} — {h['description'] or 'no description'}"
            )
        lines.append("")
    return "\n".join(lines)


def render_compat_md(reg: dict) -> str:
    lines = [
        "# Compatibility matrix",
        "",
        "Operational metadata for every hook. Generated from `hooks.registry.yaml`.",
        "",
        "| Hook | Event | Blocks? | Network? | Writes files? | Platforms | Tests |",
        "|------|-------|---------|----------|----------------|-----------|-------|",
    ]
    for h in sorted(reg["hooks"], key=lambda x: (x["category"], x["id"])):
        lines.append(
            f"| [`{h['id']}`]({h['path']}) | {fmt_event(h)} | "
            f"{fmt_yes_no(h['blocks_actions'])} | "
            f"{fmt_yes_no(h['network_access'])} | "
            f"{fmt_yes_no(h['writes_files'])} | "
            f"{fmt_platforms(h.get('platforms') or [])} | "
            f"{fmt_yes_no(bool(h.get('tests')))} |"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    reg = load_registry()
    targets = {
        "docs/hooks.md": render_hooks_md(reg),
        "docs/events.md": render_events_md(reg),
        "docs/compatibility.md": render_compat_md(reg),
    }
    for rel, content in targets.items():
        p = REPO / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        print(f"wrote {rel} ({len(content.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
