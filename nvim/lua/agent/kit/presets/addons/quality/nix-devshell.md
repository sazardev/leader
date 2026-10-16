<!-- name: Nix dev shell -->
<!-- desc: flake.nix dev shell with every tool pinned by the lockfile; direnv loads it -->
<!-- for: all -->

## Stack

| Dev | Nix flake dev shell (`flake.nix` + `flake.lock`), loaded by direnv (`.envrc`: `use flake`) | Bit-for-bit reproducible toolchain on Linux and macOS |

## Project layout

```
flake.nix                      devShells.default: the toolchain, linters, CLIs
flake.lock                     pinned inputs (committed)
.envrc                         use flake
```

## Commands

| Dev shell | `nix develop` |

## Conventions

- Every tool in the Commands table comes from the dev shell; `flake.lock` is updated in its own commit (`nix flake update`).

## Rules for agents

- Add new tools to `flake.nix`, never to a global install.
- Never edit `flake.lock` by hand.
