# C / C++ with CMake: configure, build, test with ctest
BUILD ?= build

.PHONY: configure debug build test format clean help

configure: ## Configure a release build
	cmake -S . -B $(BUILD) -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

debug: ## Configure a debug build
	cmake -S . -B $(BUILD) -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

build: ## Build (configures first when needed)
	@test -d $(BUILD) || $(MAKE) --no-print-directory configure
	cmake --build $(BUILD) -j

test: build ## Run the tests with ctest
	ctest --test-dir $(BUILD) --output-on-failure

format: ## Format with clang-format
	find src include -name '*.[ch]' -o -name '*.[ch]pp' 2>/dev/null | xargs clang-format -i

clean: ## Remove the build directory
	rm -rf $(BUILD)

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
