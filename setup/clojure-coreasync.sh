#!/bin/sh
# Clojure + core.async setup for cheby-compare (the `clojure-coreasync` variant). Idempotent;
# safe to run any number of times.
#
# Needs what setup/clojure.sh needs: Homebrew's `clojure` (the Clojure CLI) and `openjdk`
# (keg-only, /opt/homebrew/opt/openjdk/bin, put on PATH by langs/clojure-coreasync.toml). This
# script
#
#   1. checks both,
#   2. downloads Clojure and org.clojure/core.async (with its dependencies, tools.analyzer.jvm and
#      friends) into ~/.m2,
#   3. AOT-compiles core.async once into build/clojure-lib/core.async-<ver>/, so that a
#      benchmark's `build` loads its classes instead of recompiling core.async and
#      tools.analyzer on every build (the same scheme as data.json in setup/clojure.sh),
#   4. resolves the deps.edn of every benchmarks/*/clojure-coreasync, filling the classpath cache
#      in build/clojure-cache/ that `build` reads.
#
# After this, `build` works offline. Run it again after adding or changing a deps.edn.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
JDK=/opt/homebrew/opt/openjdk/bin
CLOJURE_VERSION=1.12.6
CORE_ASYNC_VERSION=1.9.865

# Same environment as langs/clojure-coreasync.toml.
PATH="$JDK:$PATH"
CLJ_CACHE="$ROOT/build/clojure-cache"
export PATH CLJ_CACHE

if [ ! -x "$JDK/java" ]; then
  echo "clojure-coreasync: missing $JDK/java; run ./setup.sh (brew install openjdk)" >&2
  exit 1
fi
if ! command -v clojure >/dev/null 2>&1; then
  echo "clojure-coreasync: installing the Homebrew formula clojure"
  brew install clojure
fi
echo "clojure-coreasync: $(clojure --version 2>&1 | head -n 1), $("$JDK/java" -version 2>&1 | head -n 1)"

mkdir -p "$CLJ_CACHE" "$ROOT/build/clojure-lib"
# The CLI is run from a directory without deps.edn, so it keeps its classpath cache in CLJ_CACHE
# (keyed by the -Sdeps text) and never writes a .cpcache into the source tree.
WORK="$ROOT/build/clojure-lib"

# Print the jar classpath (no source paths) for a deps map, downloading what is missing.
jars() {
  (cd "$WORK" && clojure -Srepro -Sdeps "$1" -Spath) | tr : '\n' | grep '^/' | paste -sd: -
}

# 2. Libraries.
LIB_DEPS="{:deps {org.clojure/clojure {:mvn/version \"$CLOJURE_VERSION\"} org.clojure/core.async {:mvn/version \"$CORE_ASYNC_VERSION\"}}}"
LIB_CP=$(jars "$LIB_DEPS")
echo "clojure-coreasync: ok       ~/.m2 has clojure $CLOJURE_VERSION and core.async $CORE_ASYNC_VERSION"

# 3. AOT-compile core.async once, into a temp dir then renamed, so a half-done compile never looks
# finished. Compiling clojure.core.async also compiles every namespace it loads (tools.analyzer,
# tools.reader, core.cache, core.memoize, ...); the go macro's state-machine namespace is named
# too, since `go` loads it only when a go block is expanded.
out="$ROOT/build/clojure-lib/core.async-$CORE_ASYNC_VERSION"
if [ -f "$out/clojure/core/async__init.class" ] && [ -f "$out/clojure/core/async/impl/ioc_macros__init.class" ]; then
  echo "clojure-coreasync: ok       build/clojure-lib/core.async-$CORE_ASYNC_VERSION"
else
  echo "clojure-coreasync: compiling core.async into build/clojure-lib/core.async-$CORE_ASYNC_VERSION"
  rm -rf "$out.tmp"
  mkdir -p "$out.tmp"
  java -Dclojure.compile.path="$out.tmp" -cp "$out.tmp:$LIB_CP" clojure.lang.Compile \
    clojure.core.async clojure.core.async.impl.ioc-macros
  rm -rf "$out"
  mv "$out.tmp" "$out"
fi

# 4. Warm the classpath cache of every benchmark, with the same -Sdeps text `build` passes.
for deps in "$ROOT"/benchmarks/*/clojure-coreasync/deps.edn; do
  [ -f "$deps" ] || continue
  bench=$(basename "$(dirname "$(dirname "$deps")")")
  jars "$(cat "$deps")" >/dev/null
  echo "clojure-coreasync: ok       benchmarks/$bench/clojure-coreasync/deps.edn resolved"
done
