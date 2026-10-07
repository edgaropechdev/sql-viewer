# Sourced by the other scripts.
# Since the macOS 27 SDK, SwiftUI's @State is a macro whose plugin ships only
# with Xcode. With bare Command Line Tools, build against the newest 26.x SDK
# and point the compiler at the toolchain's swift-testing macro plugin.
SWIFT_FLAGS=()
if [[ -z "${SDKROOT:-}" ]]; then
  toolchain="$(xcode-select -p)"
  if ! find "$toolchain" -path '*host/plugins*' -name 'libSwiftUIMacros*' -print -quit 2>/dev/null | grep -q .; then
    sdk="$(ls -d "$toolchain"/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1 || true)"
    if [[ -n "$sdk" ]]; then
      export SDKROOT="$sdk"
      SWIFT_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$toolchain/usr/lib/swift/host/plugins/testing")
      echo "Usando SDK $(basename "$sdk") (sin plugin SwiftUIMacros en $toolchain)" >&2
    fi
  fi
fi
