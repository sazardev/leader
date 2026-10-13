#!/bin/sh
# Agent setup from the terminal: detects backends (Claude Code, OpenCode, Ollama CPU/CUDA, LM Studio, llama.cpp...),
# models and hardware; starts / downloads / sets the selection ONLY if you ask for it with a flag.
#   scripts/agent-setup.sh                      report (exit 0 if a backend is ready, 1 if not)
#   scripts/agent-setup.sh --start              starts `ollama serve` if it does not respond
#   scripts/agent-setup.sh --pull qwen2.5-coder:7b   downloads a model (can be repeated)
#   scripts/agent-setup.sh --auto               applies the recommendation with the models you already have
#   scripts/agent-setup.sh --use ollama/qwen2.5-coder:7b@light   sets backend/model (without @light = main)
#   scripts/agent-setup.sh --json               the full snapshot as JSON
# Combinable: scripts/agent-setup.sh --start --pull qwen2.5-coder:3b --auto
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v nvim >/dev/null 2>&1 || { echo "agent-setup: nvim is not in PATH" >&2; exit 2; }

# arguments → Lua table (with escaped quotes), so we do not depend on how nvim handles its own flags
args=""
for a in "$@"; do
  esc=$(printf '%s' "$a" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g")
  args="$args'$esc',"
done

# Without the user config (-u NONE): the agent is plain Lua on the runtimepath, so no plugins load, nothing is installed and it
# runs in ~1 s even on a machine where the plugins are not installed yet (which is when the installer calls it)
out="$(NVIM_NO_LOCAL=1 NVIM_LIGHT=0 \
  nvim -u NONE --headless --cmd "set rtp^=$ROOT/nvim" \
    -c "lua vim.defer_fn(function() require('agent.setup').cli({ $args }) end, 300)" 2>&1)"
code=$?
printf '%s\n' "$out" | tr -d '\r'
exit "$code"
