#!/bin/sh
# Clojure setup for cheby-compare. Idempotent; safe to run any number of times.
#
# Clojure needs Homebrew's `clojure` (the Clojure CLI) and `openjdk` (keg-only,
# /opt/homebrew/opt/openjdk/bin, put on PATH by langs/clojure.toml). This script
#
#   1. checks both,
#   2. downloads the libraries into ~/.m2 (Clojure itself and clojure.data.json, the one
#      third-party library, for json_roundtrip),
#   3. AOT-compiles clojure.data.json once into build/clojure-lib/data.json-<ver>/, so that a
#      benchmark's `build` loads its classes instead of recompiling it (see langs/clojure.md),
#   4. resolves the deps.edn of every benchmarks/*/clojure, filling the classpath cache in
#      build/clojure-cache/ that `build` reads.
#
# After this, `build` works offline. Run it again after adding or changing a deps.edn.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
JDK=/opt/homebrew/opt/openjdk/bin
CLOJURE_VERSION=1.12.6
DATA_JSON_VERSION=2.5.2

# Same environment as langs/clojure.toml.
PATH="$JDK:$PATH"
CLJ_CACHE="$ROOT/build/clojure-cache"
export PATH CLJ_CACHE

if [ ! -x "$JDK/java" ]; then
  echo "clojure: missing $JDK/java; run ./setup.sh (brew install openjdk)" >&2
  exit 1
fi
if ! command -v clojure >/dev/null 2>&1; then
  echo "clojure: installing the Homebrew formula clojure"
  brew install clojure
fi
echo "clojure: $(clojure --version 2>&1 | head -n 1), $("$JDK/java" -version 2>&1 | head -n 1)"

mkdir -p "$CLJ_CACHE" "$ROOT/build/clojure-lib"
# The CLI is run from a directory without deps.edn, so it keeps its classpath cache in CLJ_CACHE
# (keyed by the -Sdeps text) and never writes a .cpcache into the source tree.
WORK="$ROOT/build/clojure-lib"

# Print the jar classpath (no source paths) for a deps map, downloading what is missing.
jars() {
  (cd "$WORK" && clojure -Srepro -Sdeps "$1" -Spath) | tr : '\n' | grep '^/' | paste -sd: -
}

# 2. Libraries.
LIB_DEPS="{:deps {org.clojure/clojure {:mvn/version \"$CLOJURE_VERSION\"} org.clojure/data.json {:mvn/version \"$DATA_JSON_VERSION\"}}}"
LIB_CP=$(jars "$LIB_DEPS")
echo "clojure: ok       ~/.m2 has clojure $CLOJURE_VERSION and data.json $DATA_JSON_VERSION"

# 3. AOT-compile data.json once, into a temp dir then renamed, so a half-done compile never
# looks finished.
out="$ROOT/build/clojure-lib/data.json-$DATA_JSON_VERSION"
if [ -f "$out/clojure/data/json__init.class" ]; then
  echo "clojure: ok       build/clojure-lib/data.json-$DATA_JSON_VERSION"
else
  echo "clojure: compiling clojure.data.json into build/clojure-lib/data.json-$DATA_JSON_VERSION"
  rm -rf "$out.tmp"
  mkdir -p "$out.tmp"
  java -Dclojure.compile.path="$out.tmp" -cp "$out.tmp:$LIB_CP" clojure.lang.Compile clojure.data.json
  rm -rf "$out"
  mv "$out.tmp" "$out"
fi

# 4. Warm the classpath cache of every benchmark, with the same -Sdeps text `build` passes.
for deps in "$ROOT"/benchmarks/*/clojure/deps.edn; do
  [ -f "$deps" ] || continue
  bench=$(basename "$(dirname "$(dirname "$deps")")")
  jars "$(cat "$deps")" >/dev/null
  echo "clojure: ok       benchmarks/$bench/clojure/deps.edn resolved"
done
