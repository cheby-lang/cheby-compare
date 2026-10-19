#!/bin/sh
# Go setup for cheby-compare. Idempotent; safe to run any number of times.
#
# Go needs nothing beyond Homebrew's `go` formula: the standard library has JSON, goroutines and
# channels. This script checks the toolchain and downloads the modules that any
# benchmarks/*/go/go.mod requires into the normal module cache (go env GOMODCACHE), so that
# `build` then works offline. Per-program build caches live under build/go/ and are made by the
# `clean` command in langs/go.toml, not here.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export GOTOOLCHAIN=local

if ! command -v go >/dev/null 2>&1; then
  echo "go: missing; run ./setup.sh (brew install go)" >&2
  exit 1
fi

version=$(go env GOVERSION)
case "$version" in
  go1.27*) echo "go: $version ($(go env GOROOT))" ;;
  *) echo "go: warning: $version found, CONVENTIONS.md pins go 1.27" >&2 ;;
esac

# Modules required by the implementations. Nothing to do for the std-only ones.
for mod in "$ROOT"/benchmarks/*/go/go.mod; do
  [ -f "$mod" ] || continue
  if grep -q '^require' "$mod"; then
    dir=$(dirname "$mod")
    echo "go: downloading modules for ${dir#"$ROOT"/}"
    (cd "$dir" && go mod download)
  fi
done
