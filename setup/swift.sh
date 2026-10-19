#!/bin/sh
# Extra setup for Swift (langs/swift.toml). Idempotent.
#
# - The compiler is the swiftc of Xcode's default toolchain (Apple Swift 6.4). Nothing is
#   installed for it; this script only checks that it and the macOS SDK are there.
# - No third-party library: Foundation (JSONDecoder/JSONEncoder) ships with the SDK.
# - Warms the shared module cache, build/swift/module-cache, that every Swift build uses
#   (-module-cache-path). swiftc compiles the SDK's and standard library's modules (Swift,
#   Foundation, Dispatch, Synchronization, ...) from their .swiftinterface files into it on first
#   use; `clean` keeps it, so a timed build compiles only the program. Re-running is cheap: when
#   the cache is current the warm-up compile takes a fraction of a second.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
export SDKROOT

if [ ! -x "$TC/swiftc" ]; then
  echo "swift: $TC/swiftc is missing; install Xcode (the Command Line Tools have no real toolchain path)" >&2
  exit 1
fi
if [ ! -d "$SDKROOT" ]; then
  echo "swift: macOS SDK not found at $SDKROOT" >&2
  exit 1
fi

CACHE="$ROOT/build/swift/module-cache"
WARM="$ROOT/build/swift/warmup"
mkdir -p "$CACHE" "$WARM"
cat >"$WARM/main.swift" <<'EOF'
// Imports every module the Swift benchmarks may use, to fill the shared module cache.
import Dispatch
import Foundation
import Synchronization

let m = Mutex(0)
m.withLock { $0 += 1 }
let data = try! JSONEncoder().encode([1, 2, 3])
_ = try! JSONDecoder().decode([Int].self, from: data)
let q = DispatchQueue(label: "warm")
q.sync {}
let t = Task { 1 }
print(await t.value)
EOF
# Same flags as langs/swift.toml's build, so the cached modules match.
(cd "$WARM" && "$TC/swiftc" -O -wmo -swift-version 6 -module-cache-path "$CACHE" -o "$WARM/main" main.swift)
"$WARM/main" >/dev/null
echo "swift: $("$TC/swiftc" --version 2>&1 | head -n 1)"
echo "swift: module cache warm at $CACHE ($(du -sh "$CACHE" | cut -f1))"
