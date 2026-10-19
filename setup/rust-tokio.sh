#!/bin/sh
# Rust + tokio setup for cheby-compare (the `rust-tokio` variant). Idempotent; safe to run any
# number of times.
#
# Needs cargo (rustc 1.99, as for the `rust` row). Downloads tokio and its dependencies, at the
# versions pinned by each implementation's Cargo.lock, into cargo's registry cache, so that
# langs/rust-tokio.toml's `build` (cargo build --offline --locked) works without the network.
# Then checks that every Cargo.lock pins the same tokio, the version the results report.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v cargo >/dev/null 2>&1; then
  echo "rust-tokio: missing cargo; install Rust (rustup) first" >&2
  exit 1
fi
echo "rust-tokio: $(cargo --version)"

for bench in ping_pong spawn_many prime_sieve; do
  dir="$ROOT/benchmarks/$bench/rust-tokio"
  (cd "$dir" && cargo fetch --locked --quiet)
  echo "rust-tokio: ok       benchmarks/$bench/rust-tokio dependencies fetched"
done

# langs/rust-tokio.toml's `version` reads tokio's version from ping_pong's Cargo.lock only, so
# every lockfile must pin the same tokio.
first=""
for bench in ping_pong spawn_many prime_sieve; do
  lock="$ROOT/benchmarks/$bench/rust-tokio/Cargo.lock"
  v=$(awk '/^name = "tokio"$/ { getline; gsub(/version = |"/, ""); print; exit }' "$lock")
  if [ -z "$v" ]; then
    echo "rust-tokio: FAILED   benchmarks/$bench/rust-tokio/Cargo.lock does not pin tokio" >&2
    exit 1
  fi
  if [ -z "$first" ]; then
    first=$v
  elif [ "$v" != "$first" ]; then
    echo "rust-tokio: FAILED   benchmarks/$bench/rust-tokio/Cargo.lock pins tokio $v, ping_pong pins $first; make them agree" >&2
    exit 1
  fi
done
echo "rust-tokio: ok       every Cargo.lock pins tokio $first"
