# C: gcc, sources in src/, objects in obj/, debug and release builds
CC ?= gcc
CFLAGS ?= -Wall -Wextra -std=c11
BIN ?= $(notdir $(CURDIR))
OBJDIR := obj
SRC := $(wildcard src/*.c)
OBJ := $(SRC:src/%.c=$(OBJDIR)/%.o)

.PHONY: build debug run memcheck format clean help

build: ## Build optimized
	$(MAKE) --no-print-directory $(BIN) CFLAGS="$(CFLAGS) -O2"

debug: ## Build with symbols, no optimization
	$(MAKE) --no-print-directory clean
	$(MAKE) --no-print-directory $(BIN) CFLAGS="$(CFLAGS) -g -O0"

run: build ## Build and run
	./$(BIN)

memcheck: debug ## Run under valgrind
	valgrind --leak-check=full ./$(BIN)

format: ## Format with clang-format
	clang-format -i $(SRC) $(wildcard src/*.h)

clean: ## Remove objects and the binary
	rm -rf $(OBJDIR) $(BIN)

$(BIN): $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^

$(OBJDIR)/%.o: src/%.c | $(OBJDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR):
	mkdir -p $@

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
