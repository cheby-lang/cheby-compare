#!/bin/sh
# Extra setup for the `erlang` language (langs/erlang.toml). Idempotent: it installs nothing that
# is already present.
#
# Needs: Erlang/OTP 27 or later (for the built-in `json` module), from Homebrew's `erlang`, and
# rebar3 for compile_large, whose SPEC asks for a rebar3 project. No third-party Erlang library
# is used by any benchmark, so nothing is fetched or pre-compiled.
set -eu

need_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "erlang setup: Homebrew is missing; install $1 by hand" >&2
    exit 1
  fi
  echo "brew install $1"
  brew install "$1"
}

command -v erl >/dev/null 2>&1 && command -v erlc >/dev/null 2>&1 || need_brew erlang
command -v rebar3 >/dev/null 2>&1 || need_brew rebar3

# OTP release and the json module (OTP 27+).
otp=$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt(0).')
if [ "$otp" -lt 27 ]; then
  echo "erlang setup: OTP $otp is too old, the benchmarks need OTP 27+ (json module)" >&2
  exit 1
fi
erl -noshell -eval 'case code:ensure_loaded(json) of {module, json} -> halt(0); _ -> halt(1) end.' \
  || { echo "erlang setup: OTP's json module is missing" >&2; exit 1; }

echo "erlang: OTP $otp ($(command -v erl)), $(rebar3 version 2>/dev/null | grep -v proxy | head -n1)"
