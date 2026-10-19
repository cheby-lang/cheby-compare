#!/bin/sh
# Install the toolchains the benchmarks need, on macOS with Homebrew.
#
# Idempotent: it checks each tool first and runs `brew install` only for the missing ones, then
# runs every setup/<lang>.sh (each idempotent too: libraries, caches, offline builds).
#
#   ./setup.sh               install what is missing, run setup/*.sh, build ../cheby if missing
#   ./setup.sh --check       only report: what is missing, which setup scripts would run
#   ./setup.sh --build-cheby also rebuild ../cheby in release mode
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
CHEBY_REPO=$(cd "$ROOT/.." && pwd)/cheby
CHECK_ONLY=0
BUILD_CHEBY=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --build-cheby) BUILD_CHEBY=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# formula:command that shows it is installed
TOOLS="
hyperfine:hyperfine
go:go
odin:odin
elixir:elixir
dotnet:dotnet
scala:scala
clojure:clojure
koka:koka
ocaml:ocaml
nim:nim
openjdk:/opt/homebrew/opt/openjdk/bin/java
"

have() {
  case "$1" in
    /*) [ -x "$1" ] ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

missing=""
for entry in $TOOLS; do
  formula=${entry%%:*}
  cmd=${entry#*:}
  if have "$cmd"; then
    printf '  ok       %s\n' "$formula"
  else
    printf '  missing  %s\n' "$formula"
    missing="$missing $formula"
  fi
done

if [ -n "$missing" ]; then
  if [ "$CHECK_ONLY" = 1 ]; then
    echo "missing:$missing (run ./setup.sh to install)"
  elif ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is not installed; install it from https://brew.sh, then run this again." >&2
    exit 1
  else
    echo "brew install$missing"
    # shellcheck disable=SC2086
    brew install $missing
  fi
else
  echo "all Homebrew toolchains are present"
fi

# Toolchains this script does not install, checked so a missing one is reported early.
for cmd in cargo python3 gleam erl zig clang++ node tsc swiftc ruby opam; do
  if ! have "$cmd"; then
    echo "  note: '$cmd' is not on PATH (needed by some langs/*.toml)"
  fi
done

# Per-language setup: setup/<lang>.sh fetches libraries, fills caches and checks the exact
# paths langs/<lang>.toml uses, so that builds work offline. Each is idempotent. Base languages
# run before their library variants (ocaml before ocaml-eio). One failing script does not stop
# the others; the failures are listed at the end.
lang_failed=""
lang_scripts=""
for script in "$ROOT"/setup/*.sh; do
  [ -f "$script" ] || continue
  case $(basename "$script") in
    *-*) ;;
    *) lang_scripts="$lang_scripts $script" ;;
  esac
done
for script in "$ROOT"/setup/*-*.sh; do
  [ -f "$script" ] && lang_scripts="$lang_scripts $script"
done
for script in $lang_scripts; do
  name=$(basename "$script" .sh)
  if [ "$CHECK_ONLY" = 1 ]; then
    printf '  would run  setup/%s.sh\n' "$name"
    continue
  fi
  echo "== setup/$name.sh"
  if ! sh "$script"; then
    echo "setup/$name.sh failed" >&2
    lang_failed="$lang_failed $name"
  fi
done
if [ "$CHECK_ONLY" = 1 ]; then
  echo "(--check runs no setup/*.sh; ./setup.sh runs them)"
fi

# Cheby: the runner uses ../cheby/target/release/cheby, or $CHEBY.
if [ "$BUILD_CHEBY" = 1 ] || [ ! -x "$CHEBY_REPO/target/release/cheby" ]; then
  if [ "$CHECK_ONLY" = 1 ]; then
    echo "cheby release binary is missing: (cd $CHEBY_REPO && cargo build --release -p cheby_cli)"
  elif [ -d "$CHEBY_REPO" ]; then
    echo "building cheby in release mode in $CHEBY_REPO"
    (cd "$CHEBY_REPO" && cargo build --release --locked -p cheby_cli)
  else
    echo "no Cheby checkout at $CHEBY_REPO; clone it there or set CHEBY to a cheby binary" >&2
  fi
else
  echo "cheby: $CHEBY_REPO/target/release/cheby"
fi

cat <<'EOF'

Notes
- The JDK is keg-only and stays off PATH. The JVM langs/*.toml files put
  /opt/homebrew/opt/openjdk/bin first in PATH through their `env`; for a shell, add
    export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
- .NET from Homebrew needs DOTNET_ROOT, which langs/csharp.toml sets; for a shell, add
    export DOTNET_ROOT="/opt/homebrew/opt/dotnet/libexec"
- The library variants' libraries come from their setup scripts, run above: setup/ocaml.sh
  installs eio_main into the private opam switch (~/.cache/cheby-compare/opam),
  setup/clojure-coreasync.sh fetches and AOT-compiles core.async, setup/rust-tokio.sh fetches
  tokio. Run a setup/<lang>.sh again after changing that language's dependencies.
- Then: python3 runner/run.py inputs && python3 runner/run.py verify
EOF

if [ -n "$lang_failed" ]; then
  echo "failed setup scripts:$lang_failed (run setup/<lang>.sh alone to see why)" >&2
  exit 1
fi
