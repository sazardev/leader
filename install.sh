#!/usr/bin/env bash
# Instala esta config de Neovim lista para trabajar: dependencias, enlace, plugins, LSP/formatters y parsers.
# Linux, WSL y macOS. Idempotente: puedes volver a correrlo cuando quieras (actualiza lo que falte).
#
#   ./install.sh                       instala todo, preguntando antes de tocar el sistema
#   ./install.sh -y                    sin preguntas
#   ./install.sh --lang go,typescript  solo esos lenguajes (el resto se desactiva en lua/local.lua)
#   ./install.sh --no-deps             no instala paquetes del sistema ni Neovim
#   ./install.sh --no-plugins          solo enlaza (plugins y herramientas se instalan al abrir nvim)
#   ./install.sh --dry-run             muestra lo que haría sin hacer nada
#
# Windows nativo: install.ps1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET="$CONFIG_HOME/nvim"
MIN_NVIM="0.11"

YES=0 DRY=0 DEPS=1 PLUGINS=1 LANGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) YES=1 ;;
    --dry-run) DRY=1 ;;
    --no-deps) DEPS=0 ;;
    --no-plugins) PLUGINS=0 ;;
    --lang) LANGS="${2:-}"; shift ;;
    --lang=*) LANGS="${1#--lang=}" ;;
    -h | --help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install: argumento desconocido: $1 (usa --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ -t 1 ]; then B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'; else B="" G="" Y="" R="" N=""; fi
step() { printf '\n%s==>%s %s\n' "$B" "$N" "$*"; }
ok() { printf '  %s✔%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die() { printf '  %s✘ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }
ask() { # ask "pregunta" → 0 si sí (con -y siempre sí; sin terminal, no)
  [ "$YES" = 1 ] && return 0
  [ -t 0 ] || return 1
  read -r -p "  $1 [S/n] " a
  case "$a" in "" | s | S | y | Y) return 0 ;; *) return 1 ;; esac
}
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; } # version_ge actual minima

OS="$(uname -s)"
SUDO=""
[ "$(id -u)" != 0 ] && have sudo && SUDO="sudo"
printf '%snvim config%s %s · %s%s\n' "$B" "$N" "$(cat "$ROOT/VERSION" 2>/dev/null || echo dev)" "$OS" "$([ -r /proc/version ] && grep -qi microsoft /proc/version && echo ' (WSL)')"

# ── 1. Paquetes del sistema ───────────────────────────────────────────────────
# Necesarios: git curl unzip tar gzip + compilador de C (treesitter). Recomendados: ripgrep (Telescope), node/npm (LSP y
# formatters de JS/TS/web vía Mason), cmake (telescope-fzf-native).
pm_install() {
  if have apt-get; then run $SUDO apt-get update -qq && run $SUDO apt-get install -y git curl unzip tar gzip build-essential ripgrep cmake nodejs npm
  elif have dnf; then run $SUDO dnf install -y git curl unzip tar gzip gcc gcc-c++ make ripgrep cmake nodejs npm
  elif have pacman; then run $SUDO pacman -S --needed --noconfirm git curl unzip tar gzip base-devel ripgrep cmake nodejs npm
  elif have zypper; then run $SUDO zypper install -y git curl unzip tar gzip gcc gcc-c++ make ripgrep cmake nodejs npm
  elif have apk; then run $SUDO apk add git curl unzip tar gzip build-base ripgrep cmake nodejs npm
  elif have brew; then run brew install git curl unzip ripgrep cmake node
  else return 1; fi
}

if [ "$DEPS" = 1 ]; then
  step "Dependencias"
  missing=()
  for c in git curl unzip tar gzip; do have "$c" || missing+=("$c"); done
  have cc || have gcc || have clang || missing+=("compilador de C")
  rec=()
  for c in rg node npm cmake; do have "$c" || rec+=("$c"); done
  if [ ${#missing[@]} -eq 0 ] && [ ${#rec[@]} -eq 0 ]; then
    ok "git curl unzip tar gzip cc rg node npm cmake"
  else
    [ ${#missing[@]} -gt 0 ] && warn "faltan (necesarios): ${missing[*]}"
    [ ${#rec[@]} -gt 0 ] && warn "faltan (recomendados): ${rec[*]}"
    if ask "¿Instalarlos con el gestor de paquetes del sistema?"; then
      pm_install || warn "no encontré apt/dnf/pacman/zypper/apk/brew: instálalos a mano"
    fi
    for c in git curl; do have "$c" || [ "$DRY" = 1 ] || die "falta $c: no se puede continuar"; done
  fi

  # Neovim >= 0.11 (nvim-treesitter y la API de LSP nueva lo exigen)
  nvim_ok() { have nvim && version_ge "$(nvim --version | sed -n '1s/[^0-9]*\([0-9.]*\).*/\1/p')" "$MIN_NVIM"; }
  if nvim_ok; then
    ok "Neovim $(nvim --version | sed -n '1s/NVIM v//p')"
  else
    cur=""
    have nvim && cur=" (hay $(nvim --version | sed -n '1s/NVIM v//p'))"
    warn "Neovim >= $MIN_NVIM no encontrado$cur"
    if [ "$OS" = Darwin ] && have brew; then
      ask "¿Instalar Neovim con brew?" && run brew install neovim
    elif [ "$OS" = Linux ]; then
      case "$(uname -m)" in x86_64) pkg=nvim-linux-x86_64 ;; aarch64 | arm64) pkg=nvim-linux-arm64 ;; *) pkg="" ;; esac
      if [ -n "$pkg" ] && ask "¿Descargar Neovim estable en ~/.local/opt/nvim (sin sudo)?"; then
        run mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
        echo "  descargando Neovim ($pkg)…"
        run curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$pkg.tar.gz" -o "/tmp/$pkg.tar.gz"
        run rm -rf "$HOME/.local/opt/nvim"
        run mkdir -p "$HOME/.local/opt/nvim"
        run tar -xzf "/tmp/$pkg.tar.gz" -C "$HOME/.local/opt/nvim" --strip-components=1
        run ln -sf "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
        export PATH="$HOME/.local/bin:$PATH"
        case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "añade ~/.local/bin a tu PATH" ;; esac
      fi
    fi
    if [ "$DRY" != 1 ]; then nvim_ok || die "necesito Neovim >= $MIN_NVIM (https://github.com/neovim/neovim/releases)"; fi
  fi
fi
[ "$DRY" = 1 ] || have nvim || die "nvim no está en el PATH"

# ── 2. Enlace ~/.config/nvim → este repo ──────────────────────────────────────
step "Enlace $TARGET"
run mkdir -p "$CONFIG_HOME"
if [ -L "$TARGET" ] && [ "$(readlink -f "$TARGET")" = "$(readlink -f "$ROOT/nvim")" ]; then
  ok "ya apunta a $ROOT/nvim"
else
  if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    backup="$TARGET.bak-$(date +%Y%m%d-%H%M%S)"
    warn "ya existía una config: la guardo en $backup"
    run mv "$TARGET" "$backup"
  fi
  run ln -s "$ROOT/nvim" "$TARGET"
  ok "$TARGET → $ROOT/nvim"
fi

# ── 3. Hooks de git (cheatsheet al día, commits convencionales) ───────────────
if [ -d "$ROOT/.git" ] && have git; then
  run git -C "$ROOT" config core.hooksPath .githooks
  ok "git hooks activados (.githooks)"
fi

# ── 4. Lenguajes ──────────────────────────────────────────────────────────────
# Todos están activos por defecto. `--lang a,b` deja solo esos (más lua) escribiendo `languages.disabled` en lua/local.lua
# (ignorado por git); si ese archivo ya existe NO se toca: te digo qué añadir.
if [ -n "$LANGS" ]; then
  step "Lenguajes: $LANGS"
  all="$(awk '/^local NAMES = \{/{f=1;next} f&&/^\}/{exit} f{gsub(/[", ]/,"");print}' "$ROOT/nvim/lua/languages/init.lua")"
  keep=",lua,$(printf '%s' "$LANGS" | tr -d ' '),"
  for l in $(printf '%s' "$LANGS" | tr ',' ' '); do
    printf '%s\n' "$all" | grep -qx "$l" || die "lenguaje desconocido: $l (disponibles: $(printf '%s' "$all" | tr '\n' ' '))"
  done
  disabled=""
  for l in $all; do case "$keep" in *",$l,"*) ;; *) disabled="$disabled\"$l\", " ;; esac; done
  snippet="return { languages = { disabled = { ${disabled%, } } } }"
  if [ -e "$ROOT/nvim/lua/local.lua" ]; then
    warn "lua/local.lua ya existe: añade dentro de su tabla →  languages = { disabled = { ${disabled%, } } }"
  elif [ "$DRY" = 1 ]; then
    printf '  [dry-run] escribiría lua/local.lua: %s\n' "$snippet"
  else
    printf -- '-- Generado por install.sh --lang (ajustes por máquina, ignorado por git)\n%s\n' "$snippet" >"$ROOT/nvim/lua/local.lua"
    ok "lua/local.lua: desactivados ${disabled%, }"
  fi
fi

# Avisos de runtimes que Mason/plugins usan para los lenguajes elegidos (no bloquean: solo evitan sorpresas)
want() { [ -z "$LANGS" ] || case ",$LANGS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
want go && ! have go && warn "Go activo pero sin \`go\` en el PATH: go.nvim y gopls no podrán instalar sus herramientas (https://go.dev/dl)"
{ want typescript || want html || want css || want json; } && ! have npm && warn "sin node/npm: los LSP y prettier de JS/TS/web no se instalarán"
want rust && ! have cargo && warn "Rust activo pero sin cargo/rustup (https://rustup.rs)"

# ── 5. Plugins, LSP/formatters/linters y parsers ──────────────────────────────
if [ "$PLUGINS" = 1 ] && [ "$DRY" != 1 ]; then
  # nvim headless escribe MUCHO progreso: todo va a un log y solo se enseñan las líneas que parecen un fallo
  LOG="${TMPDIR:-/tmp}/nvim-config-install.log"
  NV_BAD=0
  done_ok() { if [ "$NV_BAD" = 0 ]; then ok "$1"; else warn "$1 — con avisos (arriba); repite ./install.sh o mira $LOG"; fi; }
  : >"$LOG"
  nv() {
    local from rc=0
    from=$(($(wc -l <"$LOG") + 1))
    timeout "${NVIM_INSTALL_TIMEOUT:-1500}" nvim --headless "$@" >>"$LOG" 2>&1 </dev/null || rc=$?
    local bad
    bad="$(tail -n +"$from" "$LOG" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | tr '\r' '\n' |
      grep -Ei 'error|failed|E[0-9]{3,4}:' | grep -v 'Finished task' | sort -u | head -8 || true)"
    NV_BAD=0
    if [ -n "$bad" ]; then NV_BAD=1; printf '%s\n' "$bad" | sed 's/^/    /'; fi
    [ "$rc" = 124 ] && warn "tiempo agotado (NVIM_INSTALL_TIMEOUT=${NVIM_INSTALL_TIMEOUT:-1500}s)"
    return 0
  }

  step "Plugins (lazy.nvim)"
  nv "+Lazy! sync" +qa
  done_ok "plugins al día (nvim/lazy-lock.json)"

  step "LSP, formatters y linters (Mason)"
  nv -c "luafile $ROOT/scripts/install-mason.lua" +qa
  done_ok "herramientas instaladas"

  step "Parsers de treesitter"
  nv -c "luafile $ROOT/scripts/install-treesitter.lua" +qa
  done_ok "parsers compilados"
elif [ "$DRY" = 1 ]; then
  step "Plugins"
  printf '  [dry-run] lazy sync · MasonToolsInstallSync · treesitter install\n'
else
  warn "plugins, herramientas y parsers: se instalan solos la primera vez que abras nvim (o corre ./install.sh sin --no-plugins)"
fi

step "Listo"
[ "$PLUGINS" = 1 ] && [ "$DRY" != 1 ] && printf '  (registro de la instalación: %s)\n' "${TMPDIR:-/tmp}/nvim-config-install.log"
ok "abre nvim: <Space> muestra los menús; CHEATSHEET.md tiene todas las teclas"
printf '  Agente de IA (opcional): ./scripts/agent-setup.sh  (o <Space>am → Setup dentro de nvim)\n'
