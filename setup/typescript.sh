#!/bin/sh
# TypeScript setup for cheby-compare (langs/typescript.toml). Idempotent; safe to run any number
# of times, and it touches the network only when @types/node is missing or at another version.
#
# - tsc 7.0 (the native, Go-based compiler) comes from Homebrew's `typescript` formula. It is one
#   executable with no daemon or build server; /opt/homebrew/bin/tsc links straight to it.
# - The runtime is the real node 24 binary of vite-plus, called by absolute path: the `node` on
#   PATH is a vite-plus shim (about 8 ms per start) and /opt/homebrew/bin/node is node 26.
# - build/typescript/ is the shared Node project of every TypeScript implementation:
#     package.json             {"type": "module"}: the package scope of every emitted {build}/*.js
#                              (each {build} is build/typescript/<bench>), so node loads them as ESM
#     node_modules/@types/node the Node type declarations, which each implementation's
#                              tsconfig.json reaches through typeRoots
#   It is a cache like Go's module cache: never committed, rebuilt by this script.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NODE_BIN=/Users/xikxp1/.vite-plus/js_runtime/node/24.22.0/bin
TSC=/opt/homebrew/bin/tsc
TYPES_NODE=24.19.2
SHARED="$ROOT/build/typescript"

if [ ! -x "$TSC" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "brew install typescript"
    brew install typescript
  else
    echo "typescript: $TSC is missing and Homebrew is not installed" >&2
    exit 1
  fi
fi
case "$("$TSC" --version)" in
  "Version 7.0"*) echo "typescript: tsc $("$TSC" --version | sed 's/Version //')" ;;
  *) echo "typescript: warning: $("$TSC" --version), CONVENTIONS.md pins tsc 7.0" >&2 ;;
esac

if [ ! -x "$NODE_BIN/node" ]; then
  echo "typescript: node 24 is missing at $NODE_BIN (install it with vite-plus: vp env install 24.22.0)" >&2
  exit 1
fi
echo "typescript: node $("$NODE_BIN/node" --version) ($NODE_BIN/node)"

mkdir -p "$SHARED"
cat > "$SHARED/package.json.new" <<JSON
{
  "name": "cheby-compare-typescript",
  "private": true,
  "type": "module",
  "devDependencies": {
    "@types/node": "$TYPES_NODE"
  }
}
JSON
if cmp -s "$SHARED/package.json.new" "$SHARED/package.json" 2>/dev/null; then
  rm "$SHARED/package.json.new"
else
  mv "$SHARED/package.json.new" "$SHARED/package.json"
fi

have=$("$NODE_BIN/node" -p 'require(process.argv[1]).version' \
  "$SHARED/node_modules/@types/node/package.json" 2>/dev/null || true)
if [ "$have" = "$TYPES_NODE" ]; then
  echo "  ok       @types/node $have ($SHARED/node_modules)"
else
  echo "typescript: npm install @types/node@$TYPES_NODE in $SHARED"
  (cd "$SHARED" && PATH="$NODE_BIN:$PATH" npm install --no-audit --no-fund --loglevel=error)
fi
