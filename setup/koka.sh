#!/bin/sh
# Setup for langs/koka.toml. Idempotent.
#
# Koka comes from Homebrew (`brew install koka`, listed in ../setup.sh) and ships its whole
# standard library, std/async included, precompiled. Nothing is downloaded: Koka has no package
# manager, and json_roundtrip writes its own parser (CONVENTIONS "Standard library first").
# This script checks the toolchain and the real Xcode clang that langs/koka.toml puts on PATH,
# then does one smoke build with the same flags as `build`. Per-benchmark std objects are compiled
# into build/koka/<bench>/koka by the `clean` command, not here.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WANT=3.2
TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
WORK="$ROOT/build/koka-setup"

if ! command -v koka >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "koka: brew install koka"
    brew install koka
  else
    echo "koka: not found and Homebrew is not installed" >&2
    exit 1
  fi
fi

VERSION=$(koka --version 2>/dev/null | sed -n 's/^version: *//p')
case "$VERSION" in
  "$WANT".*) ;;
  *) echo "koka: warning: found $VERSION, langs/koka.toml is written for $WANT" >&2 ;;
esac

if [ ! -x "$TC/clang" ] || [ ! -d "$SDK" ]; then
  echo "koka: the Xcode toolchain ($TC/clang) or the macOS SDK is missing; install Xcode" >&2
  exit 1
fi

STAMP="$WORK/.ok-$VERSION"
if [ -f "$STAMP" ]; then
  echo "koka: $VERSION, smoke build ok ($(PATH="$TC:$PATH" koka --version | sed -n 's/^cc *: *//p'))"
  exit 0
fi

echo "koka: smoke build in $WORK"
mkdir -p "$WORK"
printf 'pub fun main()\n  println("ok")\n' > "$WORK/main.kk"
(cd "$WORK" && PATH="$TC:$PATH" SDKROOT="$SDK" \
  koka -O2 -v0 --builddir="$WORK/koka" -o "$WORK/main" main.kk >/dev/null)
[ "$("$WORK/main")" = ok ]
rm -rf "$WORK/koka" "$WORK/main" "$WORK/main.kk"
touch "$STAMP"
echo "koka: $VERSION, smoke build ok"
