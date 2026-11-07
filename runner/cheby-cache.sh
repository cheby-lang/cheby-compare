#!/bin/sh
# Resets a Cheby build cache to one that holds the standard library and no benchmark, so that a
# timed build compiles the program and reuses std, as other languages reuse theirs
# (CONVENTIONS.md, "langs/<lang>.toml").
#
# Usage: cheby-cache.sh <cheby> <cache dir>
#
# The seed is <cache dir>.std. An untimed build of runner/cheby-seed fills it, once per cheby
# binary: compiled code is keyed by the compiler, so another binary's seed is of no use.
set -eu

cheby=$1
cache=$2
seed=$cache.std
here=$(cd "$(dirname "$0")" && pwd)
stamp=$(shasum -a 256 "$cheby")

if [ "$(cat "$seed.stamp" 2>/dev/null)" != "$stamp" ]; then
  mkdir -p "$(dirname "$seed")"
  rm -rf "$seed"
  (cd "$here/cheby-seed" && CHEBY_CACHE=$seed "$cheby" build -o "$seed.bin")
  rm -f "$seed.bin"
  printf '%s\n' "$stamp" >"$seed.stamp"
fi

rm -rf "$cache"
cp -Rp "$seed" "$cache"
