#!/bin/sh
# Scala setup for cheby-compare. Idempotent; safe to run any number of times.
#
# Scala needs Homebrew's `scala` formula (Scala 3.10 distribution; it pulls in `scala-cli`) and
# `openjdk` (keg-only, /opt/homebrew/opt/openjdk). langs/scala.toml builds with
# `scala-cli compile --server=false -S 3.10.0` and sets COURSIER_MODE=offline, so every jar a
# build needs must already sit in the Coursier cache (~/Library/Caches/Coursier). This script
# fills it, online, by compiling once:
#
#   1. hello_world: scala3-compiler 3.10.0 and its dependencies, scala-library 3.10.0;
#   2. a probe with ujson 4.4.3 (com.lihaoyi::ujson, the JSON library json_roundtrip may use);
#   3. every benchmarks/*/scala directory whose sources have a `//> using dep` directive, so a
#      dependency a group agent adds is fetched by running this script again;
#   4. one compile through the Bloop server, which fetches Bloop and scala3-sbt-bridge for the
#      warm-compile measurement. A server this script starts is stopped again; one that was
#      already running is left alone. SCALA_SETUP_NO_BLOOP=1 skips this step.
#
# Throwaway outputs go to build/scala-setup/ (git-ignored). After this, `build` works offline.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
JDK_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
SCALA=3.10.0
UJSON=4.4.3
WORK="$ROOT/build/scala-setup"

if [ ! -x "$JDK_HOME/bin/java" ]; then
  echo "scala: missing $JDK_HOME/bin/java; run ./setup.sh (brew install openjdk)" >&2
  exit 1
fi
if ! command -v scala-cli >/dev/null 2>&1; then
  echo "scala: scala-cli is not on PATH; run ./setup.sh (brew install scala)" >&2
  exit 1
fi

export JAVA_HOME="$JDK_HOME"
export PATH="$JDK_HOME/bin:$PATH"
unset COURSIER_MODE   # setup is the one place that may download

echo "scala: scala-cli $(scala-cli version --cli --offline), $(java -version 2>&1 | head -n 1)"

# compile <name> <source dir> [extra scala-cli options]: one cold compile into $WORK/<name>.
compile() {
  name=$1 src=$2
  shift 2
  out="$WORK/$name"
  rm -rf "$out"
  mkdir -p "$out"
  if scala-cli compile --jvm system -S "$SCALA" --workspace "$out/ws" -d "$out/classes" "$@" "$src" \
    >"$out/log" 2>&1; then
    echo "scala: ok       $name"
  else
    cat "$out/log" >&2
    echo "scala: compile failed for $name ($src)" >&2
    exit 1
  fi
}

mkdir -p "$WORK/probe-src"
compile hello_world "$ROOT/benchmarks/hello_world/scala" --server=false

cat >"$WORK/probe-src/main.scala" <<EOF
//> using dep com.lihaoyi::ujson:$UJSON
@main def main(): Unit = println(ujson.write(ujson.read("[1]")))
EOF
compile ujson-probe "$WORK/probe-src" --server=false

for dir in "$ROOT"/benchmarks/*/scala; do
  [ -d "$dir" ] || continue
  if grep -qs '^//> *using  *dep' "$dir"/*.scala; then
    bench=$(basename "$(dirname "$dir")")
    compile "deps-$bench" "$dir" --server=false
  fi
done

if [ "${SCALA_SETUP_NO_BLOOP:-0}" != 1 ]; then
  started=0
  if ! scala-cli --power bloop 2>/dev/null | grep -q 'is running'; then
    scala-cli --power bloop start --jvm system >"$WORK/bloop.log" 2>&1
    started=1
  fi
  compile bloop-probe "$ROOT/benchmarks/hello_world/scala" --bloop-jvm system
  if [ "$started" = 1 ]; then
    scala-cli --power bloop exit >>"$WORK/bloop.log" 2>&1 || true
  fi
fi

echo "scala: Coursier cache ready; builds run offline (COURSIER_MODE=offline in langs/scala.toml)"
