#!/usr/bin/env bash
# Builds build/SQL Viewer.app (release, arm64, ad-hoc signed).
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  also copy to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."

# Static archives linked into the binary (see Package.swift); build-time only.
for lib in mysql-client/lib/libmysqlclient.a openssl@3/lib/libssl.a zstd/lib/libzstd.a; do
  if [[ ! -e "/opt/homebrew/opt/$lib" ]]; then
    echo "Falta /opt/homebrew/opt/$lib: brew install mysql-client" >&2
    exit 1
  fi
done

source scripts/toolchain.sh

swift build -c release --arch arm64
bin_dir="$(swift build -c release --arch arm64 --show-bin-path)"

app="build/SQL Viewer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/SQLViewer" "$app/Contents/MacOS/SQLViewer"
cp Support/Info.plist "$app/Contents/Info.plist"
cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# A stable identity keeps keychain "Always Allow" valid across rebuilds;
# see scripts/create-signing-identity.sh. Ad-hoc works but re-prompts.
identity="SQL Viewer Local Signing"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
  codesign --force --sign "$identity" "$app"
else
  echo "Aviso: firma ad-hoc; el llavero pedirá permiso tras cada build (scripts/create-signing-identity.sh)" >&2
  codesign --force --sign - "$app"
fi
echo "Listo: $app"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "$HOME/Applications/SQL Viewer.app"
  mkdir -p "$HOME/Applications"
  cp -R "$app" "$HOME/Applications/"
  echo "Instalado en ~/Applications/SQL Viewer.app"
fi
