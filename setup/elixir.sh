#!/bin/sh
# Extra setup for the `elixir` language (langs/elixir.toml). Idempotent: run it as often as you
# like; it installs nothing that is already present.
#
# Needs: Elixir 1.18 or later (for the built-in JSON module) on Erlang/OTP, from Homebrew's
# `elixir`. No benchmark uses a third-party library today, so normally nothing is fetched.
# When a benchmarks/<bench>/elixir/mix.exs declares deps (it then has a mix.lock), this script
# installs Hex if needed, fetches the locked deps into build/elixir/<bench>/deps and compiles
# them into build/elixir/<bench>/_build/prod/lib/<dep>, the paths langs/elixir.toml uses, so that
# `build` runs offline and `clean` keeps them.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ELIXIR_EBIN=/opt/homebrew/opt/elixir/lib/elixir/lib/elixir/ebin

need_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "elixir setup: Homebrew is missing; install $1 by hand" >&2
    exit 1
  fi
  echo "brew install $1"
  brew install "$1"
}

command -v erl >/dev/null 2>&1 || need_brew erlang
command -v elixir >/dev/null 2>&1 && command -v mix >/dev/null 2>&1 || need_brew elixir

# langs/elixir.toml's `run` names Elixir's ebin by its Homebrew opt path.
if [ ! -f "$ELIXIR_EBIN/Elixir.Kernel.beam" ]; then
  echo "elixir setup: $ELIXIR_EBIN not found; fix the path in langs/elixir.toml's run" >&2
  exit 1
fi

# Elixir 1.18+ for the JSON module.
ver=$(elixir --short-version)
major=${ver%%.*}
rest=${ver#*.}
minor=${rest%%.*}
if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 18 ]; }; then
  echo "elixir setup: Elixir $ver is too old, the benchmarks need 1.18+ (JSON module)" >&2
  exit 1
fi

# `run` lists the consolidated protocols last in one -pa, relying on erl putting the last
# directory of `-pa A B` first on the code path (OTP 29). Check that this still holds.
probe=$(mktemp -d)
mkdir -p "$probe/a" "$probe/b"
first=$(erl -noshell -pa "$probe/a" "$probe/b" \
  -eval 'io:put_chars(hd(code:get_path())), halt(0).')
rm -rf "$probe"
case "$first" in
  */b) ;;
  *)
    echo "elixir setup: erl -pa no longer puts its last directory first ($first);" >&2
    echo "  reorder the -pa list in langs/elixir.toml so consolidated/ comes first on the path" >&2
    exit 1
    ;;
esac

# Third-party deps, only for projects that declare them.
for dir in "$ROOT"/benchmarks/*/elixir; do
  [ -f "$dir/mix.exs" ] || continue
  [ -f "$dir/mix.lock" ] || continue
  bench=$(basename "$(dirname "$dir")")
  build="$ROOT/build/elixir/$bench"
  if [ ! -d "${MIX_HOME:-$HOME/.mix}/archives" ] || ! ls "${MIX_HOME:-$HOME/.mix}/archives" | grep -q '^hex'; then
    echo "elixir: installing Hex"
    mix local.hex --force
  fi
  (
    cd "$dir"
    export MIX_ENV=prod MIX_BUILD_ROOT="$build/_build" MIX_DEPS_PATH="$build/deps"
    mix deps.get --check-locked
    mix deps.compile
  )
  echo "elixir: $bench dependencies ready"
done

echo "elixir: Elixir $ver, Erlang/OTP $(erl -noshell -eval 'io:put_chars(erlang:system_info(otp_release)), halt(0).') ($(command -v elixir))"
