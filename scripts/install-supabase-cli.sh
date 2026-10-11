#!/usr/bin/env bash
# Installs the pinned Supabase CLI into a project-local directory after
# verifying its SHA-256 checksum. Nothing is installed globally.
# Usage: scripts/install-supabase-cli.sh <install-dir>
set -euo pipefail

VERSION="2.120.0"
install_dir="${1:?usage: $0 <install-dir>}"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform="darwin_arm64"; sha256="3b8546cc61aeabab6fd1f68edc7f664ebdfa96bdd6a9b18d8d612708f430ae28" ;;
  Darwin-x86_64) platform="darwin_amd64"; sha256="4c6fd79d3feaab3ba404f18044e6abee09d73c39376491476cb64880b3822f46" ;;
  Linux-x86_64) platform="linux_amd64"; sha256="7074584113aa00495beeac661c41fb09f1ddd0a483cd7333894b0d080086dc6e" ;;
  Linux-aarch64 | Linux-arm64) platform="linux_arm64"; sha256="f1747691843837be981fba9f92bf30bf1ddb8cee937ba3806454325af12a8ffc" ;;
  *) echo "error: unsupported platform $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

if [ -x "$install_dir/supabase" ] && [ "$("$install_dir/supabase" --version)" = "$VERSION" ]; then
  echo "Supabase CLI $VERSION already installed in $install_dir"
  exit 0
fi

archive="supabase_${VERSION}_${platform}.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --output "$tmp/$archive" \
  "https://github.com/supabase/cli/releases/download/v${VERSION}/${archive}"

if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/$archive" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$tmp/$archive" | cut -d' ' -f1)"
fi
if [ "$actual" != "$sha256" ]; then
  echo "error: checksum mismatch for $archive (expected $sha256, got $actual)" >&2
  exit 1
fi

tar -xzf "$tmp/$archive" -C "$tmp"
mkdir -p "$install_dir"
# `supabase` delegates some commands to the `supabase-go` binary beside it.
for binary in supabase supabase-go; do
  install -m 0755 "$tmp/$binary" "$install_dir/$binary"
done
"$install_dir/supabase" --version
