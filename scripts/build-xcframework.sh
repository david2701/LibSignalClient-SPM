#!/usr/bin/env bash
# Build SignalFfi.xcframework from upstream signalapp/libsignal SOURCE (no bitcode → xcframework-able),
# sync the matching Swift sources + FFI headers, produce the zip, and patch Package.swift with the
# release URL + SPM checksum. Reproducible; run in CI (macOS) or locally.
#
#   Usage: scripts/build-xcframework.sh <libsignal-version>   e.g. 0.79.1
#
# Requires: rustup (+ iOS targets), protoc, Xcode (xcodebuild/lipo), swift.
set -euo pipefail

VERSION="${1:?usage: build-xcframework.sh <version, e.g. 0.79.1>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER_REPO="${GITHUB_REPOSITORY:-david2701/LibSignalClient-SPM}"
OUT="$REPO_ROOT/build"; rm -rf "$OUT"; mkdir -p "$OUT"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "==> cloning signalapp/libsignal v$VERSION"
git clone --depth 1 --branch "v${VERSION}" https://github.com/signalapp/libsignal "$WORK/ls"
cd "$WORK/ls"

TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
for t in "${TARGETS[@]}"; do
  echo "==> building libsignal_ffi for $t"
  rustup target add "$t"
  CARGO_BUILD_TARGET="$t" swift/build_ffi.sh --release
done

echo "==> fat simulator slice"
lipo -create \
  "target/aarch64-apple-ios-sim/release/libsignal_ffi.a" \
  "target/x86_64-apple-ios/release/libsignal_ffi.a" \
  -output "$WORK/libsignal_ffi_sim.a"

echo "==> headers (this version's SignalFfi module)"
HDRS="$WORK/headers"; mkdir -p "$HDRS"
cp swift/Sources/SignalFfi/signal_ffi.h swift/Sources/SignalFfi/signal_ffi_testing.h \
   swift/Sources/SignalFfi/module.modulemap "$HDRS/"

echo "==> create SignalFfi.xcframework"
rm -rf "$OUT/SignalFfi.xcframework"
xcodebuild -create-xcframework \
  -library "target/aarch64-apple-ios/release/libsignal_ffi.a" -headers "$HDRS" \
  -library "$WORK/libsignal_ffi_sim.a" -headers "$HDRS" \
  -output "$OUT/SignalFfi.xcframework"

echo "==> zip + checksum"
( cd "$OUT" && zip -qry SignalFfi.xcframework.zip SignalFfi.xcframework )
CHECKSUM="$(swift package --package-path "$REPO_ROOT" compute-checksum "$OUT/SignalFfi.xcframework.zip")"
echo "checksum=$CHECKSUM"

echo "==> sync Swift sources + headers for v$VERSION into the mirror"
rm -rf "$REPO_ROOT/Sources/LibSignalClient" && mkdir -p "$REPO_ROOT/Sources/LibSignalClient"
cp -R swift/Sources/LibSignalClient/. "$REPO_ROOT/Sources/LibSignalClient/"
rm -rf "$REPO_ROOT/ffi-headers" && mkdir -p "$REPO_ROOT/ffi-headers" && cp "$HDRS"/* "$REPO_ROOT/ffi-headers/"

echo "==> patch Package.swift (version + url + checksum)"
URL="https://github.com/${OWNER_REPO}/releases/download/${VERSION}/SignalFfi.xcframework.zip"
python3 - "$REPO_ROOT/Package.swift" "$VERSION" "$URL" "$CHECKSUM" <<'PY'
import re, sys
path, version, url, checksum = sys.argv[1:5]
s = open(path).read()
s = re.sub(r'let libsignalVersion = "[^"]*"', f'let libsignalVersion = "{version}"', s)
s = re.sub(r'url: "[^"]*"', f'url: "{url}"', s)
s = re.sub(r'checksum: "[0-9a-f]{64}"', f'checksum: "{checksum}"', s)
open(path, "w").write(s)
PY

echo "DONE. Artifact: $OUT/SignalFfi.xcframework.zip  checksum=$CHECKSUM"
