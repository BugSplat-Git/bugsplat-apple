#!/bin/bash
# Builds bugsplat-native for macOS and assembles Frameworks/BugSplatNative.xcframework, the binary
# target Package.swift links during development and in CI.
#
#   scripts/build-native.sh [--native DIR] [--ref REF] [--crashpad-root DIR] [--out PATH] [--sign IDENTITY]
#
#   --native         a bugsplat-native checkout (default: ./native, cloned at --ref when missing)
#   --ref            branch/tag/commit of bugsplat-native to clone (default: $BUGSPLAT_NATIVE_REF or main)
#   --crashpad-root  a Crashpad checkout with a GN build in out/mac-release (default: <native>/crashpad-work/crashpad;
#                    built with depot_tools when missing, see bugsplat-native/docs/GETTING-STARTED.md)
#   --out            xcframework path (default: Frameworks/BugSplatNative.xcframework)
#
# Requires Xcode, CMake and Ninja (brew install cmake ninja).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
NATIVE="$REPO/native"
REF="${BUGSPLAT_NATIVE_REF:-main}"
CRASHPAD_ROOT=""
OUT="$REPO/Frameworks/BugSplatNative.xcframework"
SIGN=""
CRASHPAD_COMMIT="${CRASHPAD_COMMIT:-db44314646cbd0825a73b58dd2b7b5f4faca64a7}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --native) NATIVE="$2"; shift 2;;
    --ref) REF="$2"; shift 2;;
    --crashpad-root) CRASHPAD_ROOT="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --sign) SIGN="$2"; shift 2;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done

if [[ ! -d "$NATIVE" ]]; then
  echo "== cloning bugsplat-native ($REF) into $NATIVE"
  git clone --depth 1 --branch "$REF" https://github.com/BugSplat-Git/bugsplat-native.git "$NATIVE"
fi
[[ -n "$CRASHPAD_ROOT" ]] || CRASHPAD_ROOT="$NATIVE/crashpad-work/crashpad"

if [[ ! -d "$CRASHPAD_ROOT/out/mac-release" ]]; then
  echo "== building Crashpad ($CRASHPAD_COMMIT) with GN into $CRASHPAD_ROOT/out/mac-release"
  WORK="$(dirname "$(dirname "$CRASHPAD_ROOT")")"
  mkdir -p "$WORK"
  if [[ ! -d "$WORK/depot_tools" ]]; then
    git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$WORK/depot_tools"
  fi
  export PATH="$WORK/depot_tools:$PATH"
  gclient --version >/dev/null
  mkdir -p "$(dirname "$CRASHPAD_ROOT")"
  (cd "$(dirname "$CRASHPAD_ROOT")" && [[ -d crashpad ]] || fetch --no-history crashpad)
  (cd "$CRASHPAD_ROOT" && git fetch --depth 1 origin "$CRASHPAD_COMMIT" && git checkout "$CRASHPAD_COMMIT" && gclient sync \
     && gn gen out/mac-release --args='is_debug=false target_cpu="arm64"' \
     && ninja -C out/mac-release client handler:crashpad_handler snapshot minidump util)
fi

BUILD="$NATIVE/build-macos"
echo "== building bugsplat-native (macOS) into $BUILD"
cmake -S "$NATIVE" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
      -DBUGSPLAT_CRASHPAD_ROOT="$CRASHPAD_ROOT" -DBUGSPLAT_BUILD_TESTS=OFF -DBUGSPLAT_BUILD_SAMPLES=OFF
cmake --build "$BUILD"

echo "== assembling $OUT"
ARGS=(--version "$(tr -d '[:space:]' < "$NATIVE/VERSION")" --macos "$BUILD" --out "$OUT" --privacy "$REPO/Sources/BugSplat/Resources/PrivacyInfo.xcprivacy")
[[ -n "$SIGN" ]] && ARGS+=(--sign "$SIGN")
"$NATIVE/bindings/swift/make-xcframework.sh" "${ARGS[@]}"
