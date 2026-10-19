#!/bin/sh
# Odin setup. Idempotent: it only checks, and installs the Homebrew formula when it is missing.
#
# Odin needs nothing beyond its Homebrew formula: the compiler, its core library (core:fmt,
# core:encoding/json, core:thread, core:sync, ...) and its llvm@22 dependency, which provides the
# `clang` that Odin links with. There is no package manager, no build cache and nothing to fetch,
# so builds work offline.
set -eu

ODIN=/opt/homebrew/opt/odin/libexec/odin
LLVM_BIN=/opt/homebrew/opt/llvm@22/bin

if [ ! -x "$ODIN" ]; then
  echo "odin: installing the Homebrew formula"
  brew install odin
fi

if [ ! -x "$LLVM_BIN/clang" ]; then
  echo "odin: $LLVM_BIN/clang is missing; langs/odin.toml links with it" >&2
  echo "      (the odin formula depends on llvm@22; try 'brew reinstall odin')" >&2
  exit 1
fi

# xcrun must find the macOS SDK: Odin asks for it on every link.
if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  echo "odin: xcrun cannot find the macOS SDK; install Xcode or the Command Line Tools" >&2
  exit 1
fi

echo "odin: $("$ODIN" version)"
