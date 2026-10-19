#!/bin/sh
# C# setup for cheby-compare. Idempotent; safe to run any number of times.
#
# C# needs Homebrew's `dotnet` formula (the .NET 10 SDK; ./setup.sh installs it). The base class
# library covers every benchmark: System.Text.Json for JSON, Tasks and System.Threading.Channels
# for concurrency. This script checks the SDK, then runs `dotnet restore` for every
# benchmarks/*/csharp/main.csproj into the same artifacts directory that langs/csharp.toml's
# `build` uses (build/csharp/<bench>/artifacts). That downloads any NuGet package a project
# references into ~/.nuget/packages and writes the restore outputs, so `build` afterwards runs a
# no-op restore that needs no network. compile_large's generated projects are restored by their
# own build.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec
DOTNET="$DOTNET_ROOT/dotnet"
export DOTNET_ROOT DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 \
  DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE=1 DOTNET_GENERATE_ASPNET_CERTIFICATE=false

if [ ! -x "$DOTNET" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "brew install dotnet"
    brew install dotnet
  else
    echo "csharp: $DOTNET is missing and Homebrew is not installed" >&2
    exit 1
  fi
fi

sdk=$("$DOTNET" --version)
case "$sdk" in
  10.*) echo "csharp: .NET SDK $sdk ($DOTNET_ROOT)" ;;
  *) echo "csharp: warning: .NET SDK $sdk found, CONVENTIONS.md pins .NET SDK 10.0" >&2 ;;
esac
if ! "$DOTNET" --list-runtimes | grep -q '^Microsoft.NETCore.App 10\.'; then
  echo "csharp: the Microsoft.NETCore.App 10.x runtime is missing" >&2
  exit 1
fi

for proj in "$ROOT"/benchmarks/*/csharp/main.csproj; do
  [ -f "$proj" ] || continue
  dir=$(dirname "$proj")
  bench=$(basename "$(dirname "$dir")")
  echo "csharp: restoring benchmarks/$bench/csharp"
  (cd "$dir" && "$DOTNET" restore --disable-build-servers -nodeReuse:false \
    --artifacts-path "$ROOT/build/csharp/$bench/artifacts" -v:q)
done
