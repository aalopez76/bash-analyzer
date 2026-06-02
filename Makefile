# ============================================================
# bash-analyzer — developer task runner
# ============================================================
# Usage: make <target>   (run `make` or `make help` for the list)
# Absolute path so GNU make finds bash on both Linux (CI) and
# Git-for-Windows / WSL, where a bare `bash` recipe is run via cmd.exe
# and fails with "system cannot find the file specified".
SHELL := /usr/bin/bash

SHELL_SOURCES := app.sh move.sh functions/*.sh tests/*.sh

.DEFAULT_GOAL := help
.PHONY: help lint test run check

help: ## Show this help
	@echo "bash-analyzer — available targets:"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
	  | awk -F':.*## ' '{ printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2 }'

lint: ## Run shellcheck on all shell scripts
	@if ! command -v shellcheck >/dev/null 2>&1; then \
	  echo "shellcheck not found. Install it: https://github.com/koalaman/shellcheck#installing"; \
	  exit 1; \
	fi
	shellcheck $(SHELL_SOURCES)

test: ## Run the full test suite (uses the whiptail mock; no real whiptail needed)
	bash tests/run_tests.sh

run: ## Launch the application (requires whiptail)
	./app.sh

check: lint test ## Run lint + tests (what CI runs)
