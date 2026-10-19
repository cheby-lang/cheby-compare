"""Writes the Clojure project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project uses the generic Clojure layout of langs/clojure.toml: deps.edn (Clojure only, the
same text as every other Clojure benchmark, so setup/clojure.sh's classpath cache covers it),
src/main.clj (namespace `main`, with :gen-class) and one namespace per module, src/m0000.clj to
src/m<M-1>.clj. The build AOT-compiles `main`, which compiles every module it requires.

Each module has a `defrecord Item`, a `Shape` written as a vector tagged with a keyword
(`[:circle r]`, `[:rect w h]`, `[:tri a b c]`, `[:empty]`) and matched with `case` on the tag,
and 20 functions. Only `base` and `entry` are public (`defn`); the rest are `defn-`. Module `i`
requires only module `i - 1`. The output follows cljfmt's default style and depends only on M.
"""

import sys
from pathlib import Path

P = 1000003

DEPS_EDN = """{:paths ["src"]
 :deps {org.clojure/clojure {:mvn/version "1.12.6"}}}
"""


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"m{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    require = f"\n  (:require [{name(i - 1)}])" if i > 0 else ""
    out = [
        f""";; Module {i} of a generated compile_large project.
(ns {name(i)}{require})

;; The modulus that keeps every value small.
(def ^:private p {P})

;; A record that make-item builds and item-score reads.
(defrecord Item [id size weight])

;; The first link of this module's chain, also called by the next module.
(defn base [x]
  (let [a (+ (* x {k[0]}) {k[1]})
        b (mod a p)]
    (mod (+ (* b {k[2]}) {k[3]}) p)))
"""
    ]
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step-{j - 1}"
        out.append(
            f"""
;; Link {j} of the chain.
(defn- step-{j} [x]
  (let [y ({prev} x)
        a (+ (* y {k[4 * j]}) x)
        b (mod (+ (quot a {k[4 * j + 1]}) {k[4 * j + 2]}) p)]
    (if (even? b)
      (mod (+ a b) p)
      (mod (+ a (* b {k[4 * j + 3]})) p))))
"""
        )
    out.append(
        f"""
;; Builds an item from x.
(defn- make-item [x]
  (->Item (mod x {k[56]}) (+ (mod x 1000) {k[57]}) (mod (* x {k[58]}) p)))

;; Reads every field of item.
(defn- item-score [{{:keys [id size weight]}}]
  (mod (+ (* id {k[59]}) (* size {k[60]}) weight) p))

;; Picks a shape from x: a vector tagged with :circle, :rect, :tri or :empty.
(defn- make-shape [x]
  (case (mod x 4)
    0 [:circle (inc (mod x {k[61]}))]
    1 [:rect (inc (mod x {k[62]})) (inc (mod x {k[63]}))]
    2 [:tri (inc (mod x {k[64]})) (inc (mod x {k[65]})) (inc (mod x {k[66]}))]
    3 [:empty]))

;; The area of shape, in whole units.
(defn- area [shape]
  (case (first shape)
    :circle (let [[_ r] shape] (* 3 r r))
    :rect (let [[_ w h] shape] (* w h))
    :tri (let [[_ a b c] shape] (+ (quot (* a b) 2) c))
    :empty {k[67]}))
"""
    )
    if i > 0:
        out.append(
            f"""
;; Calls into the previous module.
(defn- link [x]
  (mod (+ ({name(i - 1)}/base x) {k[68]}) p))
"""
        )
    else:
        out.append(
            f"""
;; The first module has no previous module to call.
(defn- link [x]
  (mod (+ x {k[68]}) p))
"""
        )
    out.append(
        """
;; The function main calls.
(defn entry [x]
  (let [s (step-13 x)
        r (item-score (make-item s))
        h (area (make-shape x))
        l (link x)]
    (mod (+ s r h l) p)))
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    requires = "\n            ".join(f"[{name(i)}]" for i in range(m))
    entries = "\n                 ".join(f"{name(i)}/entry" for i in range(m))
    return f""";; Entry point of a generated compile_large project. It calls every module's entry once,
;; in order, and prints a checksum.
(ns main
  (:gen-class)
  (:require {requires}))

;; The modulus that keeps every value small.
(def ^:private p {P})

(defn -main [& _args]
  (let [entries [{entries}]]
    (println (reduce (fn [s entry] (mod (+ (* s 31) (entry s)) p)) 0 entries))))
"""


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if not 1 <= m <= 9999:
        sys.exit("M must be between 1 and 9999")
    out = Path(sys.argv[2])
    src = out / "src"
    src.mkdir(parents=True, exist_ok=True)
    (out / "deps.edn").write_text(DEPS_EDN)
    (src / "main.clj").write_text(main_module(m))
    for i in range(m):
        (src / f"{name(i)}.clj").write_text(module(i))


if __name__ == "__main__":
    main()
