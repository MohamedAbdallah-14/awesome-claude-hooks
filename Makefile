.PHONY: help lint shellcheck contract test docs registry all install-deps doctor pages-serve demo bench

help:
	@echo "Targets:"
	@echo "  make install-deps   Install shellcheck, bats-core, jq, pyyaml"
	@echo "  make shellcheck     Run shellcheck -S warning across the repo"
	@echo "  make contract       Run scripts/lint-hooks.sh"
	@echo "  make registry       Rebuild hooks.registry.{yaml,json} from headers"
	@echo "  make docs           Rebuild docs/{hooks,events,compatibility}.md from registry"
	@echo "  make lint           shellcheck + contract"
	@echo "  make test           bats -r tests"
	@echo "  make doctor         Diagnostic: tool versions + bash-3.2 hook warnings (always exit 0)"
	@echo "  make all            registry + docs + lint + test"
	@echo "  make pages-serve    Copy registry into docs-site/ and serve it on http://localhost:8000"
	@echo "  make demo           Re-record demo.cast and re-render assets/demo.gif"
	@echo "  make bench          Run hook latency benchmarks; write docs/benchmarks.md"

install-deps:
	@if command -v brew >/dev/null 2>&1; then \
	  brew install shellcheck bats-core jq && \
	  python3 -m pip install --user --break-system-packages pyyaml; \
	elif command -v apt-get >/dev/null 2>&1; then \
	  sudo apt-get update && sudo apt-get install -y shellcheck bats jq python3-yaml; \
	else \
	  echo "Install shellcheck, bats-core, jq, pyyaml manually for your platform" >&2; \
	  exit 1; \
	fi

shellcheck:
	@shellcheck -S warning hooks/**/*.sh hooks/_lib/*.sh scripts/*.sh

contract:
	@bash scripts/lint-hooks.sh

registry:
	@python3 scripts/build-registry.py

docs: registry
	@python3 scripts/render-docs.py

lint: shellcheck contract

test:
	@# Stub real-world notification binaries so test runs never leak
	@# desktop notifications, sounds, or webhooks into the maintainer's
	@# machine. Per-test setups already stub the same binaries, but this
	@# belt-and-braces stub catches any test that forgets.
	@stub=$$(mktemp -d); \
	for bin in osascript notify-send afplay paplay aplay terminal-notifier curl wget tmux; do \
	  printf '#!/usr/bin/env bash\nexit 0\n' > "$$stub/$$bin"; \
	  chmod +x "$$stub/$$bin"; \
	done; \
	PATH="$$stub:$$PATH" bats -r tests; \
	rc=$$?; rm -rf "$$stub"; exit $$rc

all: registry docs lint test

# Full bench is opt-in (slow) — `make all` deliberately does not run it.
bench-quick:
	@bash scripts/bench-hooks.sh --quick

# Diagnostic-only — never fails CI. Reports tool presence/versions and which
# hooks would warn under bash 3.2 (the macOS /bin/bash). Useful for debugging
# contributor environments without gating on it.
doctor:
	@set +e; \
	  ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$$*"; }; \
	  bad()  { printf '  \033[0;31m✗\033[0m %s\n' "$$*"; }; \
	  hdr()  { printf '\n\033[1m%s\033[0m\n' "$$*"; }; \
	  hdr "Toolchain"; \
	  if command -v shellcheck >/dev/null 2>&1; then ok "shellcheck $$(shellcheck --version | awk '/^version:/ {print $$2}')"; else bad "shellcheck not found"; fi; \
	  if command -v bats       >/dev/null 2>&1; then ok "bats $$(bats --version 2>&1 | head -1)"; else bad "bats not found"; fi; \
	  if command -v jq         >/dev/null 2>&1; then ok "jq $$(jq --version 2>/dev/null)"; else bad "jq not found"; fi; \
	  if command -v python3    >/dev/null 2>&1; then ok "$$(python3 --version 2>&1)"; else bad "python3 not found"; fi; \
	  if python3 -c 'import yaml' 2>/dev/null; then ok "pyyaml $$(python3 -c 'import yaml; print(yaml.__version__)')"; else bad "pyyaml not importable"; fi; \
	  if command -v bash       >/dev/null 2>&1; then ok "$$(bash --version | head -1)"; else bad "bash not found"; fi; \
	  hdr "Settings"; \
	  if [ -f "$$HOME/.claude/settings.json" ]; then \
	    if bash scripts/hook-doctor.sh >/dev/null 2>&1; then ok "$$HOME/.claude/settings.json passes hook-doctor"; \
	    else bad "$$HOME/.claude/settings.json has issues — run: bash scripts/hook-doctor.sh"; fi; \
	  else \
	    printf '  \033[1;33m·\033[0m no $$HOME/.claude/settings.json (skipping hook-doctor)\n'; \
	  fi; \
	  hdr "Bash 3.2 compatibility (would warn under macOS /bin/bash)"; \
	  warn_out=$$(bash scripts/lint-hooks.sh 2>&1 | grep ': warning: ' || true); \
	  if [ -z "$$warn_out" ]; then ok "all hooks compatible with bash 3.2"; \
	  else printf '%s\n' "$$warn_out" | sed 's/^/  /' ; \
	       count=$$(printf '%s\n' "$$warn_out" | wc -l | tr -d ' '); \
	       printf '  \033[1;33m⚠\033[0m %s hook(s) flagged\n' "$$count"; fi; \
	  echo ""; \
	  exit 0

# Serve the static catalog browser locally.
# `app.js` does fetch('./registry.json'), so we copy the canonical registry
# in first. The trap-on-INT keeps Ctrl-C clean (no `make: *** [pages-serve]
# Error 130`). Port is overridable:
#   make pages-serve PORT=8080
demo:
	@command -v asciinema >/dev/null 2>&1 || { echo "asciinema not found — brew install asciinema"; exit 1; }
	@command -v agg       >/dev/null 2>&1 || { echo "agg not found — brew install agg"; exit 1; }
	@asciinema rec --overwrite --command 'bash demo/demo.sh' \
	  --rows 28 --cols 100 --idle-time-limit 1 demo/demo.cast
	@agg --cols 100 --rows 28 --speed 1.5 --font-size 14 demo/demo.cast assets/demo.gif
	@echo "Wrote demo/demo.cast and assets/demo.gif"

bench:
	@bash scripts/bench-hooks.sh

PORT ?= 8000
pages-serve:
	@cp hooks.registry.json docs-site/registry.json
	@echo "Serving docs-site/ on http://localhost:$(PORT) (Ctrl-C to stop)"
	@cd docs-site && bash -c 'trap "exit 0" INT; python3 -m http.server $(PORT)'
