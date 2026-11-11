# Support

Leader is a small, maintainer-led project. There is no support contract and no SLA, but questions are welcome and
answered when there is time.

## Before asking

1. Read the [README](README.md) and the [documentation](https://leader.sazardev.stream/docs/) (or the
   [offline copy](docs/offline.html) — one file, no network).
2. Search the [issues](https://github.com/sazardev/leader/issues) and
   [discussions](https://github.com/sazardev/leader/discussions); someone may have hit the same thing.
3. Run `:checkhealth` in Neovim and keep its output. For the desktop app, `leader --version` and the GPU/backend matter.

## Where to go

| You want… | Go to |
|---|---|
| a question, an idea, a setup help, to show what you built | [Discussions](https://github.com/sazardev/leader/discussions) |
| to report a reproducible bug | [Bug report](https://github.com/sazardev/leader/issues/new?template=bug_report.yml) |
| to request a feature | [Feature request](https://github.com/sazardev/leader/issues/new?template=feature_request.yml) |
| to report a vulnerability | [SECURITY.md](SECURITY.md) — **never a public issue** |
| to contribute code or docs | [CONTRIBUTING.md](CONTRIBUTING.md) |
| the plan | [ROADMAP.md](ROADMAP.md) |
| the rules of the community | [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |

## What to include in a bug report

- **Version**: `leader --version` (desktop app) and `git -C <clone> rev-parse --short HEAD` (config).
- **Environment**: OS and version, WSL or native, terminal or desktop app, GPU/backend for rendering issues.
- **Install method**: the one-liner, the `.deb`, a source checkout, Arch.
- **Steps**: the smallest sequence that shows the problem; the command or keys, the file type, the language.
- **Observed vs expected**: what happened, what you expected.
- **Logs**: `:messages`, the relevant part of `~/.local/state/nvim/log` (or `stdpath("log")`), a screenshot or a short
  recording for UI issues. Remove private data first.
- **A minimal config**: does it still happen with `nvim --clean` plus the plugin, or with `NVIM_NO_LOCAL=1`? If you can,
  use `lua/local.lua` to disable the packs/tools that are not involved.

AI-assisted reports are fine; please check the output and remove anything private before posting.

## Commercial support

There is no paid support offering at the moment. If your company depends on Leader and wants a maintenance or
integration agreement, open a discussion with the *Support* label and we can talk about it.

## A note on time

Leader is built in the open, around a full-time job. A polite bump after a week is fine; a bump every hour is not. If a
fix matters to you and you can write the failing test, the patch is much easier to land.
