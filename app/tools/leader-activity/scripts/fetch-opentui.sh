#!/usr/bin/env bash
set -euo pipefail

version="0.9.9"
release_url="https://github.com/anomalyco/opentui/releases/download/v${version}"

usage() {
  cat <<'EOF'
Usage: scripts/fetch-opentui.sh [--all]

Downloads the official OpenTUI native v0.9.9 archive for this host, verifies its
pinned SHA-256, and extracts it to vendor/opentui-native.

  --all   download and verify all four supported archives as well
  -h, --help
EOF
}

verify_all=false
case "${1:-}" in
  "") ;;
  --all) verify_all=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

host_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os:$arch" in
    Linux:x86_64|Linux:amd64) printf '%s\n' linux-x64 ;;
    Linux:aarch64|Linux:arm64) printf '%s\n' linux-arm64 ;;
    Darwin:x86_64|Darwin:amd64) printf '%s\n' darwin-x64 ;;
    Darwin:arm64|Darwin:aarch64) printf '%s\n' darwin-arm64 ;;
    *) printf 'unsupported host: %s %s\n' "$os" "$arch" >&2; return 1 ;;
  esac
}

expected_sha() {
  case "$1" in
    linux-x64) printf '%s\n' abd03e0d1fd8ad79948f133cae9cc97421a9116802b81929465deb7bc0365660 ;;
    linux-arm64) printf '%s\n' 629e3c5777578da3cc743de5bdbd22f594163b56a326b03e43d6ed8c831d46ad ;;
    darwin-x64) printf '%s\n' f25ef248dad776a85f5fdc497c904e35f2e299a67fed6d724141b0ae24d5399b ;;
    darwin-arm64) printf '%s\n' c576d7ac40dfa0d9a50343c338da0936e5f89cf4c3f1132f6a830a5873c382b5 ;;
    *) return 1 ;;
  esac
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'need sha256sum or shasum\n' >&2
    return 1
  fi
}

fetch() {
  local platform="$1" archive expected actual
  archive="opentui-native-v${version}-${platform}.zip"
  expected="$(expected_sha "$platform")"
  printf 'Downloading %s\n' "$archive"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 3 --connect-timeout 15 \
    --output "$tmp/$archive" "$release_url/$archive"
  actual="$(sha256 "$tmp/$archive")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'SHA-256 mismatch for %s\n  expected %s\n  actual   %s\n' "$archive" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'Verified %s  %s\n' "$archive" "$actual"
}

for tool in curl unzip mktemp awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'missing required tool: %s\n' "$tool" >&2
    exit 1
  fi
done

platform="$(host_platform)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/leader-opentui.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fetch "$platform"
host_archive="$tmp/opentui-native-v${version}-${platform}.zip"

if "$verify_all"; then
  mkdir -p "$root/vendor/opentui-archives"
  for other in linux-x64 linux-arm64 darwin-x64 darwin-arm64; do
    if [[ "$other" != "$platform" ]]; then
      fetch "$other"
    fi
    cp "$tmp/opentui-native-v${version}-${other}.zip" "$root/vendor/opentui-archives/"
  done
fi

listing="$tmp/archive-list.txt"
unzip -Z1 "$host_archive" > "$listing"
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$listing"; then
  printf 'unsafe path in native archive\n' >&2
  exit 1
fi

staging="$root/vendor/.opentui-native.$$"
destination="$root/vendor/opentui-native"
rm -rf "$staging"
mkdir -p "$staging"
unzip -q "$host_archive" -d "$staging"

for required in opentui.h libopentui.a; do
  if [[ ! -f "$staging/$required" ]]; then
    printf 'native archive is missing %s\n' "$required" >&2
    rm -rf "$staging"
    exit 1
  fi
done
case "$platform" in
  linux-*) shared=libopentui.so ;;
  darwin-*) shared=libopentui.dylib ;;
esac
if [[ ! -f "$staging/$shared" ]]; then
  printf 'native archive is missing %s\n' "$shared" >&2
  rm -rf "$staging"
  exit 1
fi

rm -rf "$destination"
mv "$staging" "$destination"
printf 'Installed OpenTUI native v%s (%s) in %s\n' "$version" "$platform" "$destination"
