#!/bin/sh
# OCaml + Eio setup for cheby-compare (the `ocaml-eio` variant). Idempotent; safe to run any
# number of times.
#
# The variant shares the opam switch of the `ocaml` row: setup/ocaml.sh already installs
# eio_main (with eio and eio_posix) next to dune and yojson. This script runs it and then checks
# that eio_main is there, so langs/ocaml-eio.toml's `build` works offline.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
sh "$HERE/ocaml.sh"

prefix="${HOME}/.cache/cheby-compare/opam/cheby-compare"
if [ ! -f "$prefix/lib/eio_main/META" ]; then
  echo "ocaml-eio: eio_main is missing from $prefix; check PACKAGES in setup/ocaml.sh" >&2
  exit 1
fi
echo "ocaml-eio: eio_main $(ls "$prefix/.opam-switch/packages" | sed -n 's/^eio_main\.//p') in $prefix"
