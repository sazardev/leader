#!/bin/sh
# Setup del agente desde la terminal: detecta backends (Claude Code, OpenCode, Ollama CPU/CUDA, LM Studio, llama.cpp...),
# modelos y hardware; arranca / descarga / fija la selección SOLO si lo pides con una bandera.
#   scripts/agent-setup.sh                      informe (exit 0 si hay un backend listo, 1 si no)
#   scripts/agent-setup.sh --start              arranca `ollama serve` si no responde
#   scripts/agent-setup.sh --pull qwen2.5-coder:7b   descarga un modelo (se puede repetir)
#   scripts/agent-setup.sh --auto               aplica la recomendación con los modelos que ya tienes
#   scripts/agent-setup.sh --use ollama/qwen2.5-coder:7b@light   fija backend/modelo (sin @light = principal)
#   scripts/agent-setup.sh --json               la foto completa en JSON
# Combinable: scripts/agent-setup.sh --start --pull qwen2.5-coder:3b --auto
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v nvim >/dev/null 2>&1 || { echo "agent-setup: nvim no está en el PATH" >&2; exit 2; }

# argumentos → tabla Lua (con comillas escapadas), para no depender de cómo nvim trata sus propios flags
args=""
for a in "$@"; do
  esc=$(printf '%s' "$a" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g")
  args="$args'$esc',"
done

out="$(NVIM_NO_LOCAL=1 NVIM_LIGHT=0 \
  nvim --headless -c "lua vim.defer_fn(function() require('agent.setup').cli({ $args }) end, 300)" 2>&1)"
code=$?
printf '%s\n' "$out" | tr -d '\r'
exit "$code"
