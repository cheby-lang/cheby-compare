#!/bin/sh
# Resets a Cheby build cache to one that holds the standard library and no benchmark, so that a
# timed build compiles the program and reuses std, as other languages reuse theirs
# (CONVENTIONS.md, "langs/<lang>.toml").
#
# Usage: cheby-cache.sh <cheby> <cache dir>
#
# The seed is <cache dir>.std. Two untimed builds of runner/cheby-seed fill it, one in each
# profile, once per cheby binary: compiled code is keyed by the compiler and by the profile, so
# another binary's seed is of no use, and a release build needs std's release code.
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
  (cd "$here/cheby-seed" && CHEBY_CACHE=$seed "$cheby" build --release -o "$seed.bin")
  rm -f "$seed.bin"
  printf '%s\n' "$stamp" >"$seed.stamp"
fi

rm -rf "$cache"
cp -Rp "$seed" "$cache"
