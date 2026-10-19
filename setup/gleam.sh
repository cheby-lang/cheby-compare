#!/bin/sh
# Gleam setup. Idempotent: run it as often as you like.
#
#   setup/gleam.sh              check the toolchain, fill Gleam's hex cache, and download the
#                               locked dependencies of every benchmarks/*/gleam project, so that
#                               `build` (langs/gleam.toml) runs offline
#   setup/gleam.sh lock BENCH   resolve benchmarks/BENCH/gleam/gleam.toml and write its
#                               manifest.toml (needs the network); run after changing deps
#
# Gleam projects are staged into build/gleam/<bench>/proj, the same place `build` uses, so the
# source tree never gets a Gleam build/ directory.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE_ROOT="$ROOT/build/gleam"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "gleam: installing the Homebrew formula $2"
    brew install "$2"
  fi
}
need gleam gleam
need erl erlang

# Copy a benchmark's project into its staging dir, exactly as langs/gleam.toml's `build` does.
stage() {
  src="$ROOT/benchmarks/$1/gleam"
  dst="$STAGE_ROOT/$1/proj"
  mkdir -p "$dst"
  rm -rf "$dst/src"
  cp -Rp "$src/gleam.toml" "$src/src" "$dst/"
  if [ -f "$src/manifest.toml" ]; then
    cp -p "$src/manifest.toml" "$dst/"
  else
    rm -f "$dst/manifest.toml"
  fi
}

if [ "${1-}" = "lock" ]; then
  bench=${2:?usage: setup/gleam.sh lock BENCH}
  [ -f "$ROOT/benchmarks/$bench/gleam/gleam.toml" ] || {
    echo "gleam: benchmarks/$bench/gleam/gleam.toml not found" >&2
    exit 1
  }
  stage "$bench"
  rm -f "$STAGE_ROOT/$bench/proj/manifest.toml"
  (cd "$STAGE_ROOT/$bench/proj" && gleam deps download)
  cp "$STAGE_ROOT/$bench/proj/manifest.toml" "$ROOT/benchmarks/$bench/gleam/manifest.toml"
  echo "gleam: wrote benchmarks/$bench/gleam/manifest.toml"
  exit 0
fi

# 1. Fill Gleam's global hex cache with the packages the benchmarks may use: the standard
#    library, gleam_erlang and gleam_otp (the concurrency benchmarks) and gleam_json
#    (json_roundtrip). The scratch project's manifest pins them after the first run.
PREFETCH="$STAGE_ROOT/_prefetch"
mkdir -p "$PREFETCH/src"
cat >"$PREFETCH/gleam.toml" <<'EOF'
name = "prefetch"
version = "1.0.0"
target = "erlang"

[dependencies]
gleam_stdlib = ">= 1.0.0 and < 2.0.0"
gleam_erlang = ">= 1.0.0 and < 2.0.0"
gleam_otp = ">= 1.0.0 and < 2.0.0"
gleam_json = ">= 3.0.0 and < 4.0.0"
EOF
[ -f "$PREFETCH/src/prefetch.gleam" ] || printf 'pub fn main() -> Nil {\n  Nil\n}\n' >"$PREFETCH/src/prefetch.gleam"
(cd "$PREFETCH" && gleam deps download)

# 2. Stage every benchmark project and download its locked dependencies into the staging dir.
for dir in "$ROOT"/benchmarks/*/gleam; do
  [ -f "$dir/gleam.toml" ] || continue
  bench=$(basename "$(dirname "$dir")")
  if [ ! -f "$dir/manifest.toml" ]; then
    echo "gleam: $bench has no manifest.toml; run: setup/gleam.sh lock $bench" >&2
    continue
  fi
  stage "$bench"
  (cd "$STAGE_ROOT/$bench/proj" && gleam deps download >/dev/null)
  echo "gleam: $bench dependencies ready"
done

echo "gleam: $(gleam --version), Erlang/OTP $(erl -noshell -eval 'io:put_chars(erlang:system_info(otp_release)), halt(0).')"
