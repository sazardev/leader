# Packaging Leader

How the desktop app (`leader`, Neovim in its own GPU window) is built, packaged, signed and installed. The config
itself is installed by the root `install.sh`; these packages carry the app and the `leader-setup` command that fetches
the config for a user.

## Install it

| System | How |
| --- | --- |
| Linux, WSL (any distro, x86_64, glibc 2.31+) | `curl -fsSL https://github.com/sazardev/leader/releases/latest/download/leader-installer.sh \| bash` |
| Debian, Ubuntu, Mint, Pop!_OS | download `leader-editor-amd64.deb` from the [latest release](https://github.com/sazardev/leader/releases/latest) and `sudo apt install ./leader-editor-amd64.deb` |
| Arch, CachyOS, Manjaro | `packaging/arch/leader-editor-bin` (prebuilt, signature checked) or `packaging/arch/leader-editor` (from source): `makepkg -si` in that folder |
| From a clone (any CPU) | `./install.sh --app` (builds it with Rust) |
| Windows | through WSL with WSLg (the Linux package above); a native build is not published yet |

The packages depend on Neovim 0.11+, git and curl. The first launch with no Neovim config runs `leader-setup` inside
the window; run it yourself any time (`leader-setup --yes`).

## Names

| What | Name |
| --- | --- |
| Product | Leader |
| Program | `leader`, and `leader-setup` |
| Packages | `leader-editor` (Debian, Arch source), `leader-editor-bin` (Arch prebuilt) |
| Application id | `io.github.sazardev.Leader` (window class, `.desktop` file, AppStream id) |
| Icon | `leader` (hicolor 16 to 512 px and scalable) |

## Verify a download

Every release carries `SHA256SUMS` and a detached signature (`.asc`) for each file. They are signed with the key
**Leader Releases**:

```
pub   ed25519 2026-10-20 [SC] [expires: 2029-10-19]
      8E43 7A79 36E4 8EAE DA88  CD73 A7DC C3DB B671 476A
uid   Leader Releases (release signing key for github.com/sazardev/leader) <sazardev@users.noreply.github.com>
```

```sh
curl -fsSLO https://raw.githubusercontent.com/sazardev/leader/master/packaging/leader-releases.asc
gpg --import leader-releases.asc
gpg --fingerprint "Leader Releases"          # must print the fingerprint above
gpg --verify SHA256SUMS.asc SHA256SUMS       # "Good signature"
sha256sum -c --ignore-missing SHA256SUMS
```

`leader-installer.sh` does the same by itself when `gpg` is installed: it imports the key, requires the fingerprint it
has built in, and refuses a signature made by any other key. Without `gpg` it only checks the SHA-256 (and says so).
The signature proves the files were made by whoever holds the key; the script and the key both come from GitHub, so
compare the fingerprint with this page (or another channel you trust) if that matters to you.

## Build the release (maintainers)

```sh
app/package.sh            # builds, writes app/dist/, signs with the key in ~/.gnupg-leader-releases
app/package.sh --no-sign  # without signing
```

`app/package/stage-tree.sh` is the one place that says what is installed (binary, `leader-setup`, `.desktop` file,
icons, AppStream metadata with the release notes from `CHANGELOG.md`, man pages, license); the tarball, the `.deb`,
`./install.sh --app` and the PKGBUILDs all use it. `app/assets/make-icons.sh` regenerates the icons from the logo.
After publishing a release, `packaging/arch/update.sh` points the PKGBUILDs at it (version, checksums, `.SRCINFO`).

The signing key lives only in `~/.gnupg-leader-releases` (no passphrase, so a release can be signed without a prompt):
protect that folder, keep an encrypted backup of it, and if it ever leaks, revoke it with the certificate in
`openpgp-revocs.d/` and publish a new key here.
