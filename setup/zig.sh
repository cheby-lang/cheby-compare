#!/bin/sh
# Setup for langs/zig.toml. Idempotent.
#
# Zig comes from Homebrew (`brew install zig`). Beyond it this only warms the dedicated global
# cache, build/zig-global-cache, by building a throwaway ReleaseFast program once. That compiles
# compiler_rt and the libSystem stubs for this target, which every later build reuses, so the first
# timed build of a benchmark does not pay for them. No third-party packages are needed: std.json
# covers json_roundtrip.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WANT=0.17
CACHE="$ROOT/build/zig-global-cache"
WORK="$ROOT/build/zig-setup"

if ! command -v zig >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "zig: brew install zig"
    brew install zig
  else
    echo "zig: not found and Homebrew is not installed" >&2
    exit 1
  fi
fi

VERSION=$(zig version)
case "$VERSION" in
  "$WANT".*) ;;
  *) echo "zig: warning: found $VERSION, the configs are written for $WANT" >&2 ;;
esac

STAMP="$CACHE/.warmed-$VERSION"
if [ -f "$STAMP" ]; then
  echo "zig: $VERSION, global cache warm ($CACHE)"
  exit 0
fi

echo "zig: warming the global cache in $CACHE"
mkdir -p "$CACHE" "$WORK"
cat > "$WORK/main.zig" <<'ZIG'
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    try writer.interface.print("ok\n", .{});
    try writer.interface.flush();
}
ZIG
ZIG_GLOBAL_CACHE_DIR="$CACHE" zig build-exe -O ReleaseFast \
  --cache-dir "$WORK/zig-cache" --name main -femit-bin="$WORK/main" "$WORK/main.zig"
"$WORK/main" >/dev/null
rm -rf "$WORK"
touch "$STAMP"
echo "zig: $VERSION, global cache warm"
