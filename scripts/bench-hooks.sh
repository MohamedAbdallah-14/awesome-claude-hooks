#!/usr/bin/env bash
# bench-hooks.sh — measure per-hook latency with synthetic payloads.
#
# For each registry entry we feed the hook a payload shaped for its event,
# run it N times, and record min / p50 / p99 / max. Output is written to
# `docs/benchmarks.md` and a machine-readable `docs/benchmarks.json`.
#
# Hooks that talk to the network (ai/* and notifications/* webhooks) are
# skipped — the goal is to surface PreToolUse/PostToolUse latency for the
# in-process gating path Claude actually waits on.
#
# Usage:
#   bash scripts/bench-hooks.sh              # 30 runs per hook
#   bash scripts/bench-hooks.sh --runs 50    # custom run count
#   bash scripts/bench-hooks.sh --quick      # 5 runs (CI smoke)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

RUNS=30
QUICK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) RUNS="$2"; shift 2 ;;
    --runs=*) RUNS="${1#--runs=}"; shift ;;
    --quick) QUICK=1; RUNS=5; shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

command -v jq      >/dev/null || { echo "jq required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

# ── stub network/notification binaries so benches don't actually fire ─────────
STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
for bin in osascript notify-send afplay paplay aplay terminal-notifier curl wget tmux; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/$bin"
  chmod +x "$STUB/$bin"
done
export PATH="$STUB:$PATH"

# Skip ai/* outright — they round-trip Anthropic and aren't on the hot path.
should_skip() {
  case "$1" in
    hooks/ai/*) return 0 ;;
  esac
  return 1
}

# Build a synthetic payload appropriate for the hook's event.
payload_for_event() {
  local event="$1" matcher="$2"
  case "$event" in
    PreToolUse|PostToolUse|PostToolUseFailure|PermissionRequest|PermissionDenied)
      if [[ "$matcher" == *"Bash"* ]]; then
        printf '{"tool_name":"Bash","tool_input":{"command":"echo hi"},"session_id":"bench","cwd":"%s","hook_event_name":"%s"}' "$REPO_ROOT" "$event"
      else
        printf '{"tool_name":"Write","tool_input":{"file_path":"src/app.ts","content":"export {}"},"session_id":"bench","cwd":"%s","hook_event_name":"%s"}' "$REPO_ROOT" "$event"
      fi
      ;;
    UserPromptSubmit)
      printf '{"prompt":"hello","session_id":"bench","cwd":"%s","hook_event_name":"UserPromptSubmit"}' "$REPO_ROOT"
      ;;
    SessionStart|SessionEnd)
      printf '{"session_id":"bench","cwd":"%s","hook_event_name":"%s"}' "$REPO_ROOT" "$event"
      ;;
    PreCompact|PostCompact)
      printf '{"transcript_path":"/tmp/no-such-transcript","session_id":"bench","hook_event_name":"%s"}' "$event"
      ;;
    Stop|SubagentStop)
      printf '{"session_id":"bench","cwd":"%s","hook_event_name":"%s"}' "$REPO_ROOT" "$event"
      ;;
    *)
      printf '{"session_id":"bench","cwd":"%s","hook_event_name":"%s"}' "$REPO_ROOT" "$event"
      ;;
  esac
}

# Time one hook invocation in milliseconds. python3 to get sub-ms resolution.
time_one_ms() {
  python3 - "$1" <<'PY' "$2"
import os, sys, subprocess, time
hook_path = sys.argv[1]
payload = sys.argv[2]
t0 = time.perf_counter()
try:
  subprocess.run(["bash", hook_path], input=payload, capture_output=True,
                 timeout=10, text=True)
except subprocess.TimeoutExpired:
  print("TIMEOUT")
  sys.exit(0)
print(f"{(time.perf_counter() - t0) * 1000:.2f}")
PY
}

# Read registry entries (path, event, matcher).
ENTRIES=$(jq -r '.hooks[] | "\(.path)\t\(.event)\t\(.matcher // "")"' hooks.registry.json)

mkdir -p docs
RESULTS_JSON=$(mktemp)
echo '[]' > "$RESULTS_JSON"

count=0
total=$(printf '%s\n' "$ENTRIES" | wc -l | tr -d ' ')

while IFS=$'\t' read -r path event matcher; do
  count=$((count + 1))
  if should_skip "$path"; then
    printf '[%d/%d] skip   %s (network)\n' "$count" "$total" "$path"
    continue
  fi
  if [[ ! -x "$path" ]]; then
    printf '[%d/%d] skip   %s (not executable)\n' "$count" "$total" "$path"
    continue
  fi

  payload=$(payload_for_event "$event" "$matcher")

  samples=()
  for ((i=0; i<RUNS; i++)); do
    ms=$(time_one_ms "$path" "$payload")
    [[ "$ms" == "TIMEOUT" ]] && { ms="10000"; }
    samples+=("$ms")
  done

  stats=$(printf '%s\n' "${samples[@]}" | python3 -c '
import sys, statistics
xs = sorted(float(l) for l in sys.stdin if l.strip())
n = len(xs)
def pct(p): return xs[min(n - 1, int(round(p / 100.0 * n)))]
print(f"{xs[0]:.2f}\t{statistics.median(xs):.2f}\t{pct(99):.2f}\t{xs[-1]:.2f}")
')
  IFS=$'\t' read -r mn p50 p99 mx <<<"$stats"
  printf '[%d/%d] %-50s  min=%6sms  p50=%6sms  p99=%6sms\n' \
    "$count" "$total" "$path" "$mn" "$p50" "$p99"

  jq --arg path "$path" --arg event "$event" \
     --argjson min "$mn" --argjson p50 "$p50" --argjson p99 "$p99" --argjson max "$mx" \
     --argjson runs "$RUNS" \
     '. + [{path: $path, event: $event, runs: $runs, min_ms: $min, p50_ms: $p50, p99_ms: $p99, max_ms: $max}]' \
     "$RESULTS_JSON" > "$RESULTS_JSON.tmp" && mv "$RESULTS_JSON.tmp" "$RESULTS_JSON"
done <<<"$ENTRIES"

cp "$RESULTS_JSON" docs/benchmarks.json

# Render a markdown report grouped by event, with per-event aggregates.
python3 - <<'PY' "$RESULTS_JSON" docs/benchmarks.md "$RUNS"
import json, sys, statistics
from collections import defaultdict
results = json.load(open(sys.argv[1]))
out = sys.argv[2]
runs = sys.argv[3]
by_event = defaultdict(list)
for r in results:
    by_event[r["event"]].append(r)

with open(out, "w") as f:
    f.write("# Hook latency benchmarks\n\n")
    f.write(f"Generated by `scripts/bench-hooks.sh` ({runs} samples per hook). "
            "All times in milliseconds. Network-bound hooks (`hooks/ai/*`) are "
            "skipped because their latency is dominated by the upstream API "
            "round trip and does not reflect the hook code path.\n\n")
    f.write("Latency floor on most platforms is ~5–15 ms (bash startup + jq parse). "
            "Anything above ~50 ms p99 is worth a closer look — it sits on the "
            "synchronous path Claude Code waits on before running the tool call.\n\n")

    # Per-event summary
    f.write("## Summary by event\n\n")
    f.write("| Event | Hooks | p50 (median across hooks) | p99 (worst hook p99) |\n")
    f.write("|-------|------:|--------------------------:|---------------------:|\n")
    for ev in sorted(by_event):
        rows = by_event[ev]
        med_p50 = statistics.median(r["p50_ms"] for r in rows)
        worst_p99 = max(r["p99_ms"] for r in rows)
        f.write(f"| {ev} | {len(rows)} | {med_p50:.1f} | {worst_p99:.1f} |\n")
    f.write("\n")

    # Detail tables
    for ev in sorted(by_event):
        rows = sorted(by_event[ev], key=lambda r: -r["p99_ms"])
        f.write(f"## {ev}\n\n")
        f.write("| Hook | min | p50 | p99 | max |\n")
        f.write("|------|----:|----:|----:|----:|\n")
        for r in rows:
            name = r["path"].split("/")[-1]
            f.write(f"| `{name}` | {r['min_ms']:.1f} | {r['p50_ms']:.1f} | "
                    f"{r['p99_ms']:.1f} | {r['max_ms']:.1f} |\n")
        f.write("\n")
PY

echo
echo "Wrote docs/benchmarks.md and docs/benchmarks.json"
