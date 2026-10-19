#!/bin/sh
# Extra setup for C++ (langs/cpp.toml). Idempotent: installs only what is missing.
#
# - The compiler is Apple clang from Xcode.app, called by its real path in the Xcode toolchain
#   with SDKROOT set to the Xcode.app macOS SDK (langs/cpp.toml), not the /usr/bin/clang++ xcrun
#   trampoline. The Command Line Tools alone are not enough. Nothing is installed for it; this
#   script only checks that the exact paths the config uses are there.
# - make, for compile_large's generated Makefile: the GNU make inside Xcode.app
#   (benchmarks/compile_large/cpp/impl.toml), also called by its real path.
# - nlohmann/json (header-only) for json_roundtrip, from Homebrew. Its headers land in
#   /opt/homebrew/opt/nlohmann-json/include, which json_roundtrip's impl.toml adds with -isystem.
set -eu

DEV=/Applications/Xcode.app/Contents/Developer
CXX="$DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
MAKE="$DEV/usr/bin/make"
SDK="$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

missing=0
for f in "$CXX" "$MAKE"; do
  if [ ! -x "$f" ]; then
    echo "cpp: $f is missing" >&2
    missing=1
  fi
done
if [ ! -d "$SDK" ]; then
  echo "cpp: $SDK is missing" >&2
  missing=1
fi
if [ "$missing" -ne 0 ]; then
  echo "cpp: langs/cpp.toml needs Xcode.app in /Applications (the Command Line Tools alone are" >&2
  echo "     not enough); install Xcode from the App Store and open it once to finish setup" >&2
  exit 1
fi

if [ -f /opt/homebrew/opt/nlohmann-json/include/nlohmann/json.hpp ]; then
  echo "  ok       nlohmann-json ($(brew list --versions nlohmann-json 2>/dev/null || echo present))"
elif command -v brew >/dev/null 2>&1; then
  echo "brew install nlohmann-json"
  brew install nlohmann-json
else
  echo "cpp: Homebrew is needed to install nlohmann-json" >&2
  exit 1
fi

echo "cpp: $("$CXX" --version | head -n 1)"
echo "cpp: $("$MAKE" --version | head -n 1)"
