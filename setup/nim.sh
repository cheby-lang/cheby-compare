#!/bin/sh
# Setup for langs/nim.toml. Idempotent.
#
# Nim comes from Homebrew (`brew install nim`, which also brings nimble). The standard library
# covers every benchmark (std/json, std/tables, std/typedthreads, system Channel[T]), so no
# third-party package is installed. Should one ever be needed, list it in NIMBLE_PKGS as
# `name@version`: it is installed into build/nimble (never ~/.nimble), and an impl.toml adds
# `--NimblePath:{root}/build/nimble/pkgs2` to its build. See langs/nim.md.
#
# Nim has no separately compiled standard library and no build daemon, so there is no cache to
# warm: every clean build regenerates and compiles the C of the std modules it uses.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WANT=2.2
NIMBLE_DIR="$ROOT/build/nimble"
NIMBLE_PKGS=""

if ! command -v nim >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "nim: brew install nim"
    brew install nim
  else
    echo "nim: not found and Homebrew is not installed" >&2
    exit 1
  fi
fi

VERSION=$(nim --version | sed -n '1s/.*Version \([0-9.]*\).*/\1/p')
case "$VERSION" in
  "$WANT".*) ;;
  *) echo "nim: warning: found $VERSION, the configs are written for $WANT" >&2 ;;
esac

for pkg in $NIMBLE_PKGS; do
  name=${pkg%@*}
  ver=${pkg#*@}
  if ls -d "$NIMBLE_DIR/pkgs2/$name-$ver-"* >/dev/null 2>&1; then
    echo "nim: $pkg present in $NIMBLE_DIR"
  else
    echo "nim: nimble install $pkg into $NIMBLE_DIR"
    nimble install -y --nimbleDir:"$NIMBLE_DIR" "$pkg"
  fi
done

echo "nim: $VERSION ($(command -v nim)), no extra setup needed"
