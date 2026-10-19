#!/bin/sh
# OCaml setup for cheby-compare. Idempotent; safe to run any number of times.
#
# The compiler is Homebrew's `ocaml` (5.5, no flambda). On top of it this script makes a private
# opam root with one switch that reuses that compiler (the `ocaml-system` package), and installs
# into it the build tool and the libraries the benchmarks may use:
#
#   dune        the build tool (langs/ocaml.toml, langs/ocaml-eio.toml)
#   yojson      JSON, for json_roundtrip (CONVENTIONS "Standard library first")
#   eio_main    the ocaml-eio library variant (ping_pong, spawn_many, prime_sieve)
#
# Root and switch, which langs/ocaml*.toml hard-code through `env`:
#   OPAMROOT = $HOME/.cache/cheby-compare/opam     switch `cheby-compare` inside it
#
# After this has run, `build` works offline: every library is compiled once, here, into the
# switch, and `clean` never touches the switch.
set -eu

export OPAMROOT="${HOME}/.cache/cheby-compare/opam"
SWITCH=cheby-compare
PACKAGES="dune yojson eio_main"
export OPAMYES=1 OPAMCOLOR=never OPAMNODEPEXTS=1

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ocaml: installing the Homebrew formula $2"
    brew install "$2"
  fi
}
need ocamlopt ocaml
need opam opam

version=$(ocamlopt -version)
case "$version" in
  5.5*) echo "ocaml: $version ($(command -v ocamlopt))" ;;
  *) echo "ocaml: warning: $version found, CONVENTIONS.md pins OCaml 5.5" >&2 ;;
esac

# 1. The opam root: no sandbox (bwrap does not exist on macOS), no shell hooks written anywhere.
if [ ! -f "$OPAMROOT/config" ]; then
  echo "ocaml: creating the opam root $OPAMROOT"
  mkdir -p "$(dirname "$OPAMROOT")"
  opam init --bare --disable-sandboxing -n
fi

# 2. The switch, on the system (Homebrew) compiler. If Homebrew upgraded OCaml since the switch
#    was made, the switch no longer matches the compiler and every library must be rebuilt, so
#    it is recreated.
if opam switch list --short 2>/dev/null | grep -qx "$SWITCH"; then
  sys=$(opam list --switch="$SWITCH" --installed --short --columns=version ocaml-system 2>/dev/null || true)
  if [ "$sys" != "$version" ]; then
    echo "ocaml: switch $SWITCH was built for OCaml '$sys', compiler is $version; recreating it"
    opam switch remove "$SWITCH"
  fi
fi
if ! opam switch list --short 2>/dev/null | grep -qx "$SWITCH"; then
  echo "ocaml: creating switch $SWITCH on ocaml-system.$version"
  opam update default
  opam switch create "$SWITCH" "ocaml-system.$version" --no-switch
fi

# 3. Packages. `opam install` is a no-op for the ones already there.
missing=""
for p in $PACKAGES; do
  opam list --switch="$SWITCH" --installed --short "$p" 2>/dev/null | grep -qx "$p" || missing="$missing $p"
done
if [ -n "$missing" ]; then
  echo "ocaml: installing$missing into $SWITCH"
  # shellcheck disable=SC2086
  opam install --switch="$SWITCH" $missing
fi

prefix=$(opam var --switch="$SWITCH" prefix)
echo "ocaml: switch $SWITCH at $prefix"
for p in $PACKAGES; do
  printf '  %s %s\n' "$p" "$(opam list --switch="$SWITCH" --installed --short --columns=version "$p")"
done
