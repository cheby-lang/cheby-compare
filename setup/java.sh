#!/bin/sh
# Java setup for cheby-compare. Idempotent; safe to run any number of times.
#
# Java needs Homebrew's `openjdk` formula (keg-only, /opt/homebrew/opt/openjdk/bin, put on PATH by
# langs/java.toml) and one third-party library: Jackson databind, for json_roundtrip only (the JDK
# has no JSON API). This script checks the JDK and downloads the Jackson jars from Maven Central
# into build/java-lib/ (git-ignored), checking each against its published SHA-1. A jar that is
# already there and matches is not downloaded again. After this, `build` works offline.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
JDK=/opt/homebrew/opt/openjdk/bin
LIB="$ROOT/build/java-lib"
CENTRAL=https://repo1.maven.org/maven2

if [ ! -x "$JDK/javac" ] || [ ! -x "$JDK/java" ]; then
  echo "java: missing $JDK/javac; run ./setup.sh (brew install openjdk)" >&2
  exit 1
fi

version=$("$JDK/java" -version 2>&1 | head -n 1)
case "$version" in
  *'"27'*) echo "java: $version ($JDK)" ;;
  *) echo "java: warning: $version found, CONVENTIONS.md pins OpenJDK 27" >&2 ;;
esac

# Jackson 3 (tools.jackson.*). Its annotations stay on the 2.x group id; 2.22 is the version the
# jackson-bom 3.2.3 names. Format: group-path artifact version.
JARS="
tools/jackson/core jackson-databind 3.2.3
tools/jackson/core jackson-core 3.2.3
com/fasterxml/jackson/core jackson-annotations 2.22
"

mkdir -p "$LIB"
echo "$JARS" | while read -r group artifact ver; do
  [ -n "$group" ] || continue
  jar="$artifact-$ver.jar"
  url="$CENTRAL/$group/$artifact/$ver/$jar"
  dest="$LIB/$jar"
  sha_file="$dest.sha1"
  if [ ! -s "$sha_file" ]; then
    curl -fsSL -o "$sha_file.tmp" "$url.sha1"
    mv "$sha_file.tmp" "$sha_file"
  fi
  want=$(cut -c1-40 "$sha_file")
  if [ -f "$dest" ] && [ "$(shasum -a 1 "$dest" | cut -c1-40)" = "$want" ]; then
    echo "java: ok       build/java-lib/$jar"
    continue
  fi
  echo "java: fetching $url"
  curl -fsSL -o "$dest.tmp" "$url"
  got=$(shasum -a 1 "$dest.tmp" | cut -c1-40)
  if [ "$got" != "$want" ]; then
    rm -f "$dest.tmp"
    echo "java: SHA-1 mismatch for $jar (got $got, want $want)" >&2
    exit 1
  fi
  mv "$dest.tmp" "$dest"
done
