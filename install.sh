#!/usr/bin/env bash
# Installs this Neovim config ready to work, in ONE command: dependencies, Neovim, link, plugins, LSPs/formatters,
# parsers and the AI agent. Linux, WSL and macOS. Idempotent: run it again whenever you want (it brings everything up to date).
#
#   curl -fsSL https://raw.githubusercontent.com/sazardev/my-nvim-setup/master/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/sazardev/my-nvim-setup/master/install.sh | bash -s -- --lang go --theme catppuccin
#
# That clones the repo into ~/.local/share/my-nvim-setup (override: NVIM_CONFIG_DIR, NVIM_CONFIG_REPO, NVIM_CONFIG_BRANCH) and
# runs its install.sh. From a clone: ./install.sh [options]. In a terminal it asks one thing, which languages to set up (a
# checklist of packs, the ones this machine already uses checked); everything else it just does (--ask prompts for the
# system packages too). An existing nvim config is moved to nvim.bak-<date>, never deleted.
#
#   --lang python,sql      those language packs (go dart typescript web python rust sql swift jvm infra yarnspinner) or
#                          single languages; `all` for every one. Skips the checklist. The base (Lua, Markdown, JSON,
#                          YAML, TOML) is always on; only the languages that are on download their LSPs and tools
#   -y, --yes              asks nothing: the packs found on this machine (also what happens with no terminal)
#   --theme catppuccin     default theme (lua/local.lua)
#   --light | --no-light   forces light mode (no resident LSP) or turns it off; without this, it is detected by RAM
#   --agent MODE           AI agent: `auto` (default: the best available), `claude/haiku`, `ollama/qwen2.5-coder:7b@light`...; `none` skips it
#   --ask                  asks before installing system packages or Neovim (default: just does it)
#   --no-deps              does not install system packages or Neovim
#   --no-plugins           only links (plugins and tools are installed when nvim is opened)
#   --dry-run              shows what it would do without doing anything
#
# Native Windows: install.ps1.
set -euo pipefail

# ── 0. One command: when run from a pipe (curl | bash) there is no repo next to the script, so fetch it and hand over ──
bootstrap() {
  local repo="${NVIM_CONFIG_REPO:-https://github.com/sazardev/my-nvim-setup.git}"
  local branch="${NVIM_CONFIG_BRANCH:-master}"
  local dest="${NVIM_CONFIG_DIR:-$HOME/.local/share/my-nvim-setup}"
  local a
  for a in "$@"; do
    if [ "$a" = --dry-run ]; then
      printf '  [dry-run] would fetch %s (%s) into %s and run its install.sh %s\n' "$repo" "$branch" "$dest" "$*"
      exit 0
    fi
  done
  command -v curl >/dev/null 2>&1 || { echo "install: curl is required" >&2; exit 1; }
  printf 'nvim config: fetching %s → %s\n' "$repo" "$dest"
  if [ -d "$dest/.git" ] && command -v git >/dev/null 2>&1; then
    git -C "$dest" pull --ff-only -q || echo "install: could not fast-forward $dest (local changes?); using it as is" >&2
  elif command -v git >/dev/null 2>&1 && [ ! -e "$dest" ]; then
    git clone -q --depth 1 --branch "$branch" "$repo" "$dest"
  else
    # no git (or a non-git folder from an earlier tarball install): a tarball needs only curl + tar
    mkdir -p "$dest"
    curl -fsSL "${repo%.git}/archive/refs/heads/$branch.tar.gz" | tar -xz --strip-components=1 -C "$dest"
  fi
  [ -f "$dest/install.sh" ] || { echo "install: could not fetch the config into $dest" >&2; exit 1; }
  NVIM_CONFIG_BOOTSTRAPPED=1 exec bash "$dest/install.sh" "$@"
}
SELF="${BASH_SOURCE[0]:-}"
case "$SELF" in "" | bash | -bash | /dev/fd/* | /proc/*) SELF="" ;; esac
if [ -z "$SELF" ] || [ ! -d "$(cd "$(dirname "$SELF")" && pwd)/nvim" ]; then bootstrap "$@"; fi

ROOT="$(cd "$(dirname "$SELF")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET="$CONFIG_HOME/nvim"
MIN_NVIM="0.11"

YES=1 DRY=0 DEPS=1 PLUGINS=1 LANGS="" THEME="" LIGHT="" AGENT="auto" QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) YES=1 QUIET=1 ;;
    --ask) YES=0 ;;
    --dry-run) DRY=1 ;;
    --no-deps) DEPS=0 ;;
    --no-plugins) PLUGINS=0 ;;
    --lang) LANGS="${2:-}"; shift ;;
    --lang=*) LANGS="${1#--lang=}" ;;
    --theme) THEME="${2:-}"; shift ;;
    --theme=*) THEME="${1#--theme=}" ;;
    --light) LIGHT=1 ;;
    --no-light) LIGHT=0 ;;
    --agent) AGENT="${2:-}"; shift ;;
    --agent=*) AGENT="${1#--agent=}" ;;
    -h | --help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "install: unknown argument: $1 (use --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ -t 1 ]; then B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'; else B="" G="" Y="" R="" N=""; fi
T0=$SECONDS
step() { T0=$SECONDS; printf '\n%s==>%s %s\n' "$B" "$N" "$*"; }
took() { printf '%ss' "$((SECONDS - T0))"; }
ok() { printf '  %s✔%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die() { printf '  %s✘ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }
ask() { # ask "question" → 0 if yes (by default always yes; with --ask it prompts; without a terminal, no)
  [ "$YES" = 1 ] && return 0
  [ -t 0 ] || return 1
  read -r -p "  $1 [Y/n] " a
  case "$a" in "" | y | Y) return 0 ;; *) return 1 ;; esac
}
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; } # version_ge current minimum

OS="$(uname -s)"
SUDO=""
[ "$(id -u)" != 0 ] && have sudo && SUDO="sudo"
printf '%snvim config%s %s · %s%s\n' "$B" "$N" "$(cat "$ROOT/VERSION" 2>/dev/null || echo dev)" "$OS" "$([ -r /proc/version ] && grep -qi microsoft /proc/version && echo ' (WSL)')"

# ── 0. Languages: the one question ────────────────────────────────────────────
# The packs come from nvim/lua/languages/packs.lua (one per line: read here with sed, nvim may not be installed yet).
# Checked to start with: the packs whose tools are on this machine. With --lang, --yes or no terminal it does not ask:
# --lang decides, otherwise the detected packs (--dry-run asks too: answering changes nothing). With a lua/local.lua already there it is not asked again
# (that file is yours: change languages in the settings panel, <leader>Sp → Languages).
PACK_IDS=() PACK_LABELS=() PACK_DETECT=() PACK_ON=()
read_packs() {
  local line id label detect
  while IFS= read -r line; do
    id="$(printf '%s' "$line" | sed -n 's/.*{ id = "\([^"]*\)".*/\1/p')"
    [ -n "$id" ] || continue
    label="$(printf '%s' "$line" | sed -n 's/.*label = "\([^"]*\)".*/\1/p')"
    detect="$(printf '%s' "$line" | sed -n 's/.*detect = { \([^}]*\)}.*/\1/p' | tr -d '",')"
    PACK_IDS+=("$id") PACK_LABELS+=("$label") PACK_DETECT+=("$detect")
    local on=0 cmd
    for cmd in $detect; do have "$cmd" && on=1; done
    PACK_ON+=("$on")
  done <"$ROOT/nvim/lua/languages/packs.lua"
}
detected_langs() {
  local out="" i
  for i in "${!PACK_IDS[@]}"; do [ "${PACK_ON[$i]}" = 1 ] && out="${out:+$out,}${PACK_IDS[$i]}"; done
  printf '%s' "${out:-none}"
}
choose_langs() {
  local i ans tok found c
  while :; do
    printf '\n  %sWhich languages?%s The base is always on: Lua, Markdown, JSON, YAML, TOML.\n' "$B" "$N"
    printf '  Only the checked ones download their LSPs, formatters and linters. Checked to start: found on this machine.\n\n'
    for i in "${!PACK_IDS[@]}"; do
      found=""
      for c in ${PACK_DETECT[$i]}; do have "$c" && found="$found$c "; done
      printf '  %3d  [%s] %-34s %s\n' "$((i + 1))" "$([ "${PACK_ON[$i]}" = 1 ] && echo x || echo ' ')" "${PACK_LABELS[$i]}" "$found"
    done
    printf '\n  Toggle by number (e.g. 3 7), a = all, n = none, Enter = continue: '
    IFS= read -r ans </dev/tty || ans=""
    [ -z "$ans" ] && break
    for tok in $ans; do
      case "$tok" in
        a | all) for i in "${!PACK_ON[@]}"; do PACK_ON[$i]=1; done ;;
        n | none) for i in "${!PACK_ON[@]}"; do PACK_ON[$i]=0; done ;;
        *[!0-9]*) printf '  %s!%s %s is not a number\n' "$Y" "$N" "$tok" ;;
        *) i=$((tok - 1)); [ "$i" -ge 0 ] && [ "$i" -lt "${#PACK_IDS[@]}" ] && PACK_ON[$i]=$((1 - PACK_ON[$i])) ;;
      esac
    done
  done
}
if [ -z "$LANGS" ] && [ ! -f "$ROOT/nvim/lua/local.lua" ]; then
  read_packs
  if [ "$QUIET" = 0 ] && { : </dev/tty; } 2>/dev/null; then
    choose_langs
  fi
  LANGS="$(detected_langs)"
  printf '  %s✔%s languages: %s\n' "$G" "$N" "$LANGS"
elif [ -z "$LANGS" ]; then
  printf '  %s✔%s languages: kept from lua/local.lua (change them in <leader>Sp → Languages)\n' "$G" "$N"
fi

# ── 1. System packages ────────────────────────────────────────────────────────
# Required: git curl unzip tar gzip + C compiler (treesitter). Recommended: ripgrep (Telescope), node/npm (LSPs and
# JS/TS/web formatters via Mason), cmake (telescope-fzf-native).
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
  step "Dependencies"
  missing=()
  for c in git curl unzip tar gzip; do have "$c" || missing+=("$c"); done
  have cc || have gcc || have clang || missing+=("C compiler")
  rec=()
  for c in rg node npm cmake; do have "$c" || rec+=("$c"); done
  if [ ${#missing[@]} -eq 0 ] && [ ${#rec[@]} -eq 0 ]; then
    ok "git curl unzip tar gzip cc rg node npm cmake"
  else
    [ ${#missing[@]} -gt 0 ] && warn "missing (required): ${missing[*]}"
    [ ${#rec[@]} -gt 0 ] && warn "missing (recommended): ${rec[*]}"
    if ask "Install them with the system package manager?"; then
      pm_install || warn "could not find apt/dnf/pacman/zypper/apk/brew: install them by hand"
    fi
    for c in git curl; do have "$c" || [ "$DRY" = 1 ] || die "$c is missing: cannot continue"; done
  fi

  # Neovim >= 0.11 (nvim-treesitter and the new LSP API require it)
  nvim_ok() { have nvim && version_ge "$(nvim --version | sed -n '1s/[^0-9]*\([0-9.]*\).*/\1/p')" "$MIN_NVIM"; }
  if nvim_ok; then
    ok "Neovim $(nvim --version | sed -n '1s/NVIM v//p')"
  else
    cur=""
    have nvim && cur=" (found $(nvim --version | sed -n '1s/NVIM v//p'))"
    warn "Neovim >= $MIN_NVIM not found$cur"
    if [ "$OS" = Darwin ] && have brew; then
      ask "Install Neovim with brew?" && run brew install neovim
    elif [ "$OS" = Linux ]; then
      case "$(uname -m)" in x86_64) pkg=nvim-linux-x86_64 ;; aarch64 | arm64) pkg=nvim-linux-arm64 ;; *) pkg="" ;; esac
      if [ -n "$pkg" ] && ask "Download stable Neovim to ~/.local/opt/nvim (no sudo)?"; then
        run mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
        echo "  downloading Neovim ($pkg)…"
        run curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$pkg.tar.gz" -o "/tmp/$pkg.tar.gz"
        run rm -rf "$HOME/.local/opt/nvim"
        run mkdir -p "$HOME/.local/opt/nvim"
        run tar -xzf "/tmp/$pkg.tar.gz" -C "$HOME/.local/opt/nvim" --strip-components=1
        run ln -sf "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
        export PATH="$HOME/.local/bin:$PATH"
        case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "add ~/.local/bin to your PATH" ;; esac
      fi
    fi
    if [ "$DRY" != 1 ]; then nvim_ok || die "Neovim >= $MIN_NVIM is required (https://github.com/neovim/neovim/releases)"; fi
  fi
fi
[ "$DRY" = 1 ] || have nvim || die "nvim is not in PATH"

# ── 2. Link ~/.config/nvim → this repo ────────────────────────────────────────
step "Link $TARGET"
run mkdir -p "$CONFIG_HOME"
if [ -L "$TARGET" ] && [ "$(readlink -f "$TARGET")" = "$(readlink -f "$ROOT/nvim")" ]; then
  ok "already points to $ROOT/nvim"
else
  if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    backup="$TARGET.bak-$(date +%Y%m%d-%H%M%S)"
    warn "a config already existed: saving it to $backup"
    run mv "$TARGET" "$backup"
  fi
  run ln -s "$ROOT/nvim" "$TARGET"
  ok "$TARGET → $ROOT/nvim"
fi

# ── 3. Git hooks (up-to-date cheatsheet, conventional commits) ────────────────
if [ -d "$ROOT/.git" ] && have git; then
  run git -C "$ROOT" config core.hooksPath .githooks
  ok "git hooks enabled (.githooks)"
fi

# ── 4. Per-machine settings ───────────────────────────────────────────────────
# `--lang`, `--theme` and `--light/--no-light` are written to lua/local.lua (git-ignored) with scripts/install-local.lua, the
# same implementation install.ps1 uses. All languages are active by default; if local.lua already exists it is NOT touched:
# it says what to add.
if [ -n "$LANGS$THEME$LIGHT" ]; then
  step "Settings (lua/local.lua)"
  if have nvim; then
    rc=0
    out="$(NVIM_INSTALL_LANGS="$LANGS" NVIM_INSTALL_THEME="$THEME" NVIM_INSTALL_LIGHT="$LIGHT" NVIM_INSTALL_DRY="$DRY" \
      nvim -u NONE --headless -l "$ROOT/scripts/install-local.lua" 2>&1)" || rc=$?
    printf '%s\n' "$out" | tr -d '\r' | while IFS= read -r line; do
      case "$line" in
        "OK "*) ok "${line#OK }" ;;
        "WARN "*) warn "${line#WARN }" ;;
        "ERR "*) printf '  %s✘ %s%s\n' "$R" "${line#ERR }" "$N" >&2 ;;
      esac
    done
    [ "$rc" = 0 ] || exit "$rc"
  else
    printf '  [dry-run] would write lua/local.lua with: lang=%s theme=%s light=%s\n' "$LANGS" "$THEME" "$LIGHT"
  fi
fi

# Warnings about runtimes that Mason/plugins use for the chosen languages (they do not block: they just avoid surprises)
LANG_NAMES="$LANGS"
if [ -n "$LANGS" ] && have nvim; then
  LANG_NAMES="$(nvim -u NONE --headless -l "$ROOT/scripts/install-local.lua" --expand "$LANGS" 2>/dev/null | tr -d '\r' || echo "$LANGS")"
fi
want() { [ -z "$LANG_NAMES" ] || case ",$LANG_NAMES," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
want go && ! have go && warn "Go is active but there is no \`go\` in PATH: go.nvim and gopls will not be able to install their tools (https://go.dev/dl)"
{ want typescript || want html || want css || want json; } && ! have npm && warn "no node/npm: the JS/TS/web LSPs and prettier will not be installed"
want rust && ! have cargo && warn "Rust is active but there is no cargo/rustup (https://rustup.rs)"
want python && ! have uv && warn "Python is active and uv is not installed: the menu runs through python3 (uv: https://docs.astral.sh/uv)"
want sql && ! have psql && ! have sqlite3 && warn "SQL is active but neither psql nor sqlite3 is installed: queries cannot run"
want swift && ! have swift && warn "Swift is active but there is no swift toolchain (https://swift.org/install): no LSP, format or build"

# ── 5. Plugins, LSPs/formatters/linters and parsers ────────────────────────────
if [ "$PLUGINS" = 1 ] && [ "$DRY" != 1 ]; then
  # headless nvim writes A LOT of progress: everything goes to a log and only lines that look like a failure are shown
  LOG="${TMPDIR:-/tmp}/nvim-config-install.log"
  NV_BAD=0
  done_ok() { if [ "$NV_BAD" = 0 ]; then ok "$1 · $(took)"; else warn "$1 — with warnings (above); re-run ./install.sh or check $LOG"; fi; }
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
    [ "$rc" = 124 ] && warn "timed out (NVIM_INSTALL_TIMEOUT=${NVIM_INSTALL_TIMEOUT:-1500}s)"
    return 0
  }

  # `restore` installs what is missing at the commits pinned in nvim/lazy-lock.json (a `sync` would update everything to
  # the latest and rewrite the lockfile). lazy.nvim bootstraps itself at its latest stable commit, so on a fresh clone that
  # one lockfile line changes: put it back to keep the clone clean.
  step "Plugins (lazy.nvim, pinned versions)"
  nv "+Lazy! restore" +qa
  [ "${NVIM_CONFIG_BOOTSTRAPPED:-}" = 1 ] && git -C "$ROOT" checkout -q -- nvim/lazy-lock.json 2>/dev/null || true
  done_ok "plugins installed"

  step "LSPs, formatters and linters (Mason)"
  nv -c "luafile $ROOT/scripts/install-mason.lua" +qa
  done_ok "tools installed"

  step "Treesitter parsers"
  nv -c "luafile $ROOT/scripts/install-treesitter.lua" +qa
  done_ok "parsers compiled"
elif [ "$DRY" = 1 ]; then
  step "Plugins"
  printf '  [dry-run] lazy restore · MasonToolsInstallSync · treesitter install\n'
else
  warn "plugins, tools and parsers: they install themselves the first time you open nvim (or run ./install.sh without --no-plugins)"
fi

# ── 6. AI agent (optional) ────────────────────────────────────────────────────
# With --agent it is configured (auto | backend/model[@light]); without the option it only shows what it detects; `none` skips it.
# It needs the plugins already installed (it uses the config), so it goes last and is skipped with --no-plugins or --dry-run.
if [ "$AGENT" != none ]; then
  step "AI agent"
  if [ "$DRY" = 1 ]; then
    printf '  [dry-run] scripts/agent-setup.sh %s\n' "$([ -n "$AGENT" ] && { [ "$AGENT" = auto ] && echo --auto || echo "--use $AGENT"; })"
  elif [ "$PLUGINS" != 1 ]; then
    warn "skipped with --no-plugins: when you first open nvim, run ./scripts/agent-setup.sh${AGENT:+ $([ "$AGENT" = auto ] && echo --auto || echo "--use $AGENT")}"
  else
    case "$AGENT" in
      "") "$ROOT/scripts/agent-setup.sh" || true ;; # report; exits 1 if no backend is ready
      auto) "$ROOT/scripts/agent-setup.sh" --auto || warn "could not apply the recommendation: <Space>am → Setup inside nvim" ;;
      *) "$ROOT/scripts/agent-setup.sh" --use "$AGENT" || warn "could not set $AGENT: <Space>am → Setup inside nvim" ;;
    esac
  fi
fi

step "Done in $((SECONDS))s"
[ "$PLUGINS" = 1 ] && [ "$DRY" != 1 ] && printf '  (install log: %s)\n' "${TMPDIR:-/tmp}/nvim-config-install.log"
ok "open nvim: <Space> shows the menus; CHEATSHEET.md has all the keys"
