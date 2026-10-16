<!-- name: GoReleaser -->
<!-- desc: release binaries for every OS/arch from a tag, checksums, SBOM, Homebrew tap -->
<!-- for: go -->
<!-- default: go-cli go-bubbletea go-wish -->

## Stack

| Release | GoReleaser (`.goreleaser.yaml`): cross-compiled archives, checksums, SBOM, Homebrew tap, on every `v*` tag | One tag = a complete, reproducible release |

## Project layout

```
.goreleaser.yaml               builds (CGO_ENABLED=0, linux/darwin/windows × amd64/arm64), archives, checksum, brews
```

## Conventions

- Version, commit and date are injected with `-ldflags "-X main.version={{.Version}}"`; `--version` prints them.
- Releases are created by CI on a pushed tag; nobody publishes from a laptop.

## Commands

| Release (dry run) | `goreleaser release --snapshot --clean` |
| Check config | `goreleaser check` |

## Rules for agents

- Never hardcode the version string: it comes from ldflags.
- `goreleaser check` must pass after any change to `.goreleaser.yaml`.
