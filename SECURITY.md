# Security policy

Leader runs an editor, plugins and an AI agent with your user's permissions. We take reports seriously and we would
rather hear about a problem early than read about it after it was exploited.

## Supported versions

| Version | Supported |
|---|---|
| `master` (next release) | ✅ fixes land here first |
| latest release (`1.18.x`) | ✅ security fixes are backported when practical |
| older releases | ⚠️ best effort; upgrade when you can |

The desktop app and the config share a version (`VERSION`). Run `leader --version` and `git -C ~/.local/share/leader rev-parse HEAD` (or `git rev-parse HEAD` in your clone) when reporting.

## Reporting a vulnerability

**Please do not open a public issue.** Use one of these private channels:

1. **GitHub private vulnerability reporting**: repository **Security** tab → *Report a vulnerability* (preferred; it
   keeps the report, the discussion and the fix in one place).
2. **Email**: `cerberusprogrammer@gmail.com` with `Leader security` in the subject.

Include:

- the version and the install method (one-liner, package, source, terminal vs desktop app);
- the operating system and, for the app, the GPU/backend (`WGPU_BACKEND`, `LEADER_TIMING=1` if relevant);
- a minimal reproduction, the impact and any logs or screenshots;
- whether the issue is already public and how you would like to be credited.

We will acknowledge the report within **72 hours**, confirm the impact, and keep you informed while we prepare a fix.
We coordinate the disclosure date with you; please give us a reasonable window before publishing. We will credit you in
the release notes unless you prefer otherwise.

## Scope

In scope:

- the installers (`install.sh`, `install.ps1`, `app/package/leader-installer.sh`, `app/package/install.sh`) and the
  release artifacts they download;
- the desktop app (`app/`, Rust + wgpu + winit + the `nvim --embed` protocol);
- the config (`nvim/`, Lua) and the pinned plugins in `nvim/lazy-lock.json`;
- the website and its deploy configuration (`docs/`, Cloudflare Pages).

Out of scope (report upstream, but tell us if Leader makes it worse):

- vulnerabilities in Neovim, NvChad, a plugin, a language server, a formatter or a model runtime;
- a backend you configured (Claude Code, OpenCode, Ollama, LM Studio, llama.cpp…) and the model's own behaviour;
- a machine that is already compromised, or a config you edited to run untrusted code.

## Security model and safe defaults

- **No telemetry.** The editor sends nothing on its own. There is no analytics in the config; the website uses no
  cookies. The only network calls are the ones you trigger (plugin/tool install, an agent action, an update check).
- **The agent runs when you ask.** Prompts and the context Leader builds (the target, types, diagnostics, project rules)
  go to the backend you selected. A local backend stays local; a cloud backend receives that context. The agent reads
  project files only; `git.commit.sensitive` keeps common secrets (`.env`, keys…) out of the AI commit diff. Treat any
  secret in the repository as readable by the model you choose.
- **Plugins are code.** Leader pins them in `nvim/lazy-lock.json`; review a plugin before adding it, and update
  deliberately with `:Lazy sync`. Mason tools and treesitter parsers are downloaded from their upstream projects.
- **Release integrity.** Every release ships `SHA256SUMS` and the installer verifies the checksum. Detached signatures
  with the `Leader Releases` key are checked when the key is available. The 1.15–1.18 assets are **unsigned** (the
  signing key was not on the build machine); the installer says so and `LEADER_VERIFY=0` is explicit. Build from source
  if you need a fully verified artifact before 1.19 signs again.
- **Secrets in the app**: the app inherits your environment and clipboard. Clipboard calls use the OS clipboard; the
  config does not write it to disk. Session and history files live under `stdpath("state")` with your user's permissions.

## Hardening tips

- Keep Neovim and the plugins current; run `:checkhealth` and `:Lazy sync` after an update.
- Use a local model (`ollama`, LM Studio, llama.cpp) for sensitive code, or a backend whose data policy you accept.
- Review `lua/local.lua` (per-machine settings, git-ignored) and the `agent` backend choice before running untrusted
  projects.
- On a shared machine, protect `~/.config/nvim`, `~/.local/share/leader` and `~/.local/state/nvim` like any other file
  with credentials in it.
- Report a leaked release key or a tampered asset immediately through the private channels above.

Thank you for helping keep Leader and its users safe.
