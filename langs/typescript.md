# TypeScript (`typescript`) guide for benchmark authors

Toolchain: tsc 7.0.2 (the native, Go-based compiler, Homebrew `typescript`) and node v24.22.0
(the real binary of vite-plus). Config: `langs/typescript.toml`. Extra setup:
`setup/typescript.sh` (idempotent).

## Layout

Every implementation is a small Node project. Copy the two manifests from
`benchmarks/hello_world/typescript/` unchanged and write the sources:

```text
benchmarks/<bench>/typescript/
  package.json   {"private": true, "type": "module"}: the .ts files are ES modules
  tsconfig.json  ES2024, NodeNext, strict, skipLibCheck, types ["node"], typeRoots (below)
  main.ts        the entry point; more modules are fine (import them as "./lib.js")
  impl.toml      optional: libs, notes, or a key override
```

`tsconfig.json` includes `*.ts` in the implementation directory, with `rootDir` `.`, so
`main.ts` is emitted to `{build}/main.js`. Keep sources in that one directory, or change
`include` if you really need subdirectories.

`setup/typescript.sh` makes the shared `build/typescript/` (git-ignored, like a module cache):

- `node_modules/@types/node` (24.19.2), reached by every tsconfig through
  `"typeRoots": ["../../../build/typescript/node_modules/@types"]`. That relative path assumes
  the implementation sits at `benchmarks/<bench>/typescript/`.
- `package.json` with `"type": "module"`. Each `{build}` is `build/typescript/<bench>/`, so this
  is the package scope of the emitted JavaScript, and node loads it as ESM.

If `build/` is wiped, run `setup/typescript.sh` again (it works offline only when the npm cache
holds @types/node; otherwise it fetches it once).

## What the config does

```text
build    = /opt/homebrew/bin/tsc -p . --outDir {build}
clean    = find {build} -name '*.js' -type f -delete
run      = /Users/xikxp1/.vite-plus/js_runtime/node/24.22.0/bin/node {build}/main.js {args}
artifact = {build}/main.js
```

- **Cold compile.** tsc 7 is a single native executable; `/opt/homebrew/bin/tsc` links straight
  to it (no node launcher). There is no daemon, no `--watch`, no `--build`, and no
  `incremental`/`composite`, so no `.tsbuildinfo` exists. Every build after `clean` checks and
  emits the whole program. Never add `incremental` or `composite` to a tsconfig (compile_large
  SPEC forbids it). hello_world: about 35 ms per clean build.
- **skipLibCheck** is on, as `tsc --init` writes it. It skips checking the bodies of
  `@types/node`, which otherwise costs about 150 ms per build. Your own code is fully checked.
- **No shell syntax in `build`**: hyperfine 2 times it without a shell. `clean` may use a shell.
- **Run** calls node 24 by absolute path. `node` on `PATH` is a vite-plus shim (about 8 ms per
  start) and `/opt/homebrew/bin/node` is node 26. Default node flags: no `--max-old-space-size`,
  `--stack-size` or `--jitless`.
- A type error makes tsc exit 2, so the runner reports a failed build (tsc still emits the .js;
  ignore it).

## Building and running by hand

From `benchmarks/<bench>/typescript/`:

```sh
/opt/homebrew/bin/tsc -p . --outDir ../../../build/typescript/<bench>
/Users/xikxp1/.vite-plus/js_runtime/node/24.22.0/bin/node ../../../build/typescript/<bench>/main.js 10
```

Emit into `build/typescript/<something>/`, so the shared `package.json` makes it ESM. Or use
the runner, which is what counts:

```sh
python3 runner/run.py verify -l typescript -b <bench> --sizes zero,test,bench --diff
```

The build log is in `build/typescript/<bench>/build.log`.

## Third-party dependencies

None should be needed: JSON is built in (`JSON.parse`, `JSON.stringify`), and the concurrency
benchmarks use a hand-written promise channel (SPECs). CONVENTIONS allows no other library.

If one were ever needed, add it to the shared project: pin it in the `package.json` that
`setup/typescript.sh` writes (next to `@types/node`) and let the script's `npm install` fetch it.
Node resolves bare imports by walking up from `{build}/main.js`, so it finds
`build/typescript/node_modules`. tsc resolves them from the source directory, which does not
see that folder, so the tsconfig would also need `"paths"` (or a `typeRoots` entry for an
`@types` package). Name it in `impl.toml` as `libs = ["name x.y.z"]`.

## Gotchas

- **TS 6+/7 defaults.** `types` defaults to `[]`, so `"types": ["node"]` is required for
  `process`, `Buffer` and `node:*` modules. `strict` is set explicitly. Import Node modules as
  `import { readFileSync } from "node:fs";` and local modules with a `.js` extension
  (`import { f } from "./lib.js";`), as NodeNext requires.
- **Arguments.** `process.argv[2]` is the first argument (`[0]` is node, `[1]` the script).
  `Number.parseInt(process.argv[2] ?? "0", 10)`; with `strict`, indexing gives `string`, not
  `string | undefined` (`noUncheckedIndexedAccess` is off).
- **Numbers are doubles.** Integers are exact up to 2^53. The SPECs keep values below that
  (Lehmer products below 2^47, sums well below 2^53), so use `number`, not `bigint`, unless a
  SPEC needs 64-bit wrapping. `/` is float division: `Math.floor(a / b)` or `Math.trunc` for
  integer division. Bitwise operators (`| & ^ << >>`) truncate to signed 32 bits; `>>> 0` gives
  unsigned 32 bits, `Math.imul` a wrapping 32-bit multiply (FNV-1a in json_roundtrip:
  `h = Math.imul(h ^ b, 16777619) >>> 0`). `1 << k` overflows for `k >= 31`: use `2 ** k`. If
  real 64-bit wrapping is unavoidable, use `BigInt.asUintN(64, ...)` and say so in `notes`.
- **Rounding.** The SPECs want half away from zero. `Math.round` rounds halves toward +infinity,
  which differs for negative halves. Use
  `const r = (x: number) => Math.sign(x) * Math.round(Math.abs(x));` unless the SPEC says
  `Math.round` is safe (nbody's table does).
- **Output.** `console.log` per line is fine for a few lines. For many lines, collect them in an
  array and write `lines.join("\n") + "\n"` once with `process.stdout.write`. Never call
  `process.exit()` after writing: on macOS a pipe to stdout is asynchronous, and `process.exit`
  dropped all but the first 128 KiB of a 5 MB write in a test. Let the program end on its own.
- **Recursion.** The default V8 stack (about 984 KiB) allows about 10,000 frames of a small
  function and fewer with more arguments (7,700 with three). Do not raise `--stack-size`. Tree
  depths in the SPECs are far below this, but write deep loops as `for`/`while`, not recursion.
- **Typed arrays** (`Float64Array`, `Int32Array`, `Uint8Array`) are the idiomatic fixed-size
  numeric arrays and what the SPECs suggest for spectral_norm, fannkuch_redux and lru_cache.
- **Concurrency.** Single-threaded event loop: tasks are `async` functions, channels are the
  SPEC's rendezvous `Channel<T>` on promises. ESM allows top-level `await`, so `main.ts` may end
  with `await main();`. No `worker_threads`.
- **Files.** `readFileSync(path, "latin1")` or `"utf8"` from `node:fs` (word_freq SPEC).
- **Maps.** `Map<string, number>` keeps insertion order; sort explicitly before printing.
  See lru_cache's SPEC for why `map.keys().next()` is not an O(1) eviction in V8.
- **compile_large.** Its generated project is built from its own directory, so the
  `../../../build/typescript/...` typeRoots path does not fit there. Have `gen.py` write an
  absolute `typeRoots` to `<repo>/build/typescript/node_modules/@types` and a
  `"type": "module"` package.json, or set `"types": []` if the modules need no Node API (the
  entry point still needs `process.argv` only if it reads arguments).
