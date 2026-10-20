# Leader: working on the editor and its desktop app. `make` lists everything; `make dev` is the real-time loop.
# (This file follows the format of the Leader tasks picker: <leader>R lists these targets with their descriptions.)

SHELL := bash
APP     := app
PROFILE ?= fast# fast (default: close to release, rebuilt in seconds), dev (debug), release
ARGS    ?=# what to open: make run ARGS="nvim/lua/gui/init.lua"
BIN      = $(CURDIR)/$(APP)/target/$(if $(filter dev,$(PROFILE)),debug,$(PROFILE))/leader
CARGO    = cd $(APP) && cargo
BUILDFLAGS = $(if $(filter dev,$(PROFILE)),,$(if $(filter release,$(PROFILE)),--release,--profile $(PROFILE)))
STYLUA  ?= $(or $(shell command -v stylua),$(wildcard $(HOME)/.local/share/nvim/mason/bin/stylua))

.DEFAULT_GOAL := help
.PHONY: help dev run open build kill timing snap restart \
        test test-app test-gui test-agent test-package check lint fmt fmt-lua docs cheatsheet \
        package install uninstall icons clean

help: ## List the targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z_-]+:.*## / { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\n  PROFILE=fast|dev|release (default fast)   ARGS="file.go" (what the window opens)\n'

# ── the real-time loop ──────────────────────────────────────────────────────
dev: ## Run Leader and rebuild / restart it on every change (Rust: rebuild, Lua: restart)
	@scripts/dev-watch.sh $(PROFILE) -- $(ARGS)

run: build ## Build and run Leader in this terminal (ARGS="file" to open files)
	@$(BIN) $(ARGS)

open: build ## Build and open Leader detached (the terminal stays free)
	@cd $(CURDIR) && { setsid $(BIN) $(ARGS) </dev/null >/dev/null 2>&1 & } ; echo "opened $(BIN)"

build: ## Build the app (PROFILE=fast|dev|release)
	@$(CARGO) build $(BUILDFLAGS) -p leader-gui 2>&1 | grep -vE "linker stderr|linker_messages|^\s*\|?\s*$$" ; test $${PIPESTATUS[0]} -eq 0
	@echo "built $(BIN) ($$($(BIN) --version))"

restart: kill open ## Close every running Leader and open a fresh one (picks up Lua changes)

kill: ## Close every Leader window started from this checkout
	@pkill -f "^$(CURDIR)/$(APP)/target/[a-z]+/leader" 2>/dev/null && echo "closed" || echo "none running"

timing: build ## Run Leader printing startup and input latency
	@LEADER_TIMING=1 $(BIN) $(ARGS)

snap: build ## Take a PNG of the window: make snap ARGS="file" KEYS=" ff" OUT=/tmp/leader.png MS=3000
	@LEADER_SNAPSHOT=$(or $(OUT),/tmp/leader.png) LEADER_SNAPSHOT_MS=$(or $(MS),3000) $(if $(KEYS),LEADER_KEYS="$(KEYS)") $(BIN) -n $(ARGS) 2>&1 | grep -v MESA

# ── checks ──────────────────────────────────────────────────────────────────
test: ## Every suite (scripts/test.sh)
	@scripts/test.sh

test-app: ## The desktop app: Lua side and Rust unit tests (add GUI=1 for the real window)
	@scripts/test-app.sh $(if $(GUI),--gui)

test-gui: ## Only the app's Lua suite (scripts/test-gui.lua), fast
	@s=$$(mktemp -d); XDG_STATE_HOME=$$s AGENT_TEST_ROOT=$(CURDIR) NVIM_NO_LOCAL=1 NVIM_LIGHT=1 nvim --headless -c "luafile scripts/test-gui.lua" 2>&1 | tr '\r' '\n' | grep -E "^(FAIL|ALL OK|FAILURES)|E5[0-9]{2}"; rm -rf $$s

test-agent: ## The agent suites
	@scripts/test-agent.sh

test-package: ## The packaging: metadata, icons, installed tree, signing key, PKGBUILDs
	@scripts/test-package.sh

check: lint test ## Lint and every suite

lint: ## clippy for the app
	@$(CARGO) clippy --release -p leader-gui 2>&1 | grep -E "^(warning|error)" -A6 | grep -vE "linker" || echo "clippy: clean"

fmt: ## cargo fmt and stylua on the Lua files you changed (never the whole tree)
	@$(CARGO) fmt
	@$(MAKE) --no-print-directory fmt-lua

fmt-lua:
	@files=$$( (git diff --name-only HEAD; git ls-files --others --exclude-standard) | grep -E '\.lua$$' | sort -u); \
	  if [ -z "$$files" ]; then echo "no changed Lua files"; elif [ -z "$(STYLUA)" ]; then echo "stylua is not installed (Mason: :MasonInstall stylua)"; else $(STYLUA) $$files && echo "formatted: $$(echo $$files | wc -w) files"; fi

docs: ## Regenerate the web docs from the Markdown (the pre-commit hook does it too)
	@scripts/gen-docs.sh --worktree

cheatsheet: ## Regenerate CHEATSHEET.md from the real keymaps
	@scripts/gen-cheatsheet.sh

# ── releases and installs ───────────────────────────────────────────────────
package: ## Build the release files in app/dist (tarball, .deb, checksums, signatures)
	@app/package.sh

install: ## Install the app from this checkout into ~/.local (menu entry, icons, manual)
	@app/install.sh

uninstall: ## Remove what `make install` put down
	@app/install.sh --uninstall

icons: ## Regenerate the icon set from app/assets/leader.svg
	@app/assets/make-icons.sh

clean: ## Remove the app's build output
	@$(CARGO) clean
