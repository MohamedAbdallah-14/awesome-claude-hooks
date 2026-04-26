.PHONY: help lint shellcheck contract test all install-deps

help:
	@echo "Targets:"
	@echo "  make install-deps   Install shellcheck, bats-core, jq (macOS via brew)"
	@echo "  make shellcheck     Run shellcheck -S warning across the repo"
	@echo "  make contract       Run scripts/lint-hooks.sh"
	@echo "  make lint           shellcheck + contract"
	@echo "  make test           bats -r tests"
	@echo "  make all            lint + test"

install-deps:
	@command -v brew >/dev/null 2>&1 && brew install shellcheck bats-core jq || \
	  (command -v apt-get >/dev/null 2>&1 && sudo apt-get update && sudo apt-get install -y shellcheck bats jq python3-yaml) || \
	  (echo "Install shellcheck, bats-core, jq manually for your platform" && exit 1)

shellcheck:
	@shellcheck -S warning hooks/**/*.sh hooks/_lib/*.sh scripts/*.sh

contract:
	@bash scripts/lint-hooks.sh

lint: shellcheck contract

test:
	@bats -r tests

all: lint test
