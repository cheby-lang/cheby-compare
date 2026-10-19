//// LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream.
////
//// Shape C of the spec: `entries` maps each key to its value and tick, `by_tick` maps each live
//// tick to its key, both in `gleam/dict`. The least recent entry has the smallest live tick,
//// found by counting `oldest` up to it.

import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

const modulus = 1_000_000_007

const lehmer_m = 2_147_483_647

const lehmer_a = 48_271

const seed = 42

const hot_percent = 80

const key_space_factor = 16

type Lru {
  Lru(
    capacity: Int,
    entries: Dict(Int, #(Int, Int)),
    by_tick: Dict(Int, Int),
    clock: Int,
    oldest: Int,
  )
}

type Stats {
  Stats(hits: Int, misses: Int, values: Int)
}

pub fn main() -> Nil {
  let assert Ok([capacity, ops, ..]) =
    plain_arguments()
    |> list.map(charlist_to_string)
    |> list.try_map(int.parse)
  let hot = capacity
  let cold = capacity * { key_space_factor - 1 }
  let cache = Lru(capacity, dict.new(), dict.new(), 0, 0)
  let #(cache, stats) = run(ops, seed, hot, cold, cache, Stats(0, 0, 0))
  io.print(
    "hits "
    <> int.to_string(stats.hits)
    <> "\nmisses "
    <> int.to_string(stats.misses)
    <> "\nvalues "
    <> int.to_string(stats.values)
    <> "\nchecksum "
    <> int.to_string(checksum(cache))
    <> "\n",
  )
}

fn run(
  n: Int,
  state: Int,
  hot: Int,
  cold: Int,
  cache: Lru,
  stats: Stats,
) -> #(Lru, Stats) {
  case n {
    0 -> #(cache, stats)
    _ -> {
      let state = state * lehmer_a % lehmer_m
      let key = pick_key(state, hot, cold)
      case get(cache, key) {
        Ok(#(value, cache)) ->
          run(n - 1, state, hot, cold, cache, {
            Stats(
              ..stats,
              hits: stats.hits + 1,
              values: { stats.values + value } % modulus,
            )
          })
        Error(Nil) ->
          run(
            n - 1,
            state,
            hot,
            cold,
            insert(cache, key, key * 2 + 1),
            Stats(..stats, misses: stats.misses + 1),
          )
      }
    }
  }
}

fn pick_key(state: Int, hot: Int, cold: Int) -> Int {
  let draw = state / 100
  case state % 100 < hot_percent {
    True -> draw % hot
    False -> hot + draw % cold
  }
}

/// A hit returns the value and makes the key the most recent.
fn get(cache: Lru, key: Int) -> Result(#(Int, Lru), Nil) {
  case dict.get(cache.entries, key) {
    Ok(#(value, old)) -> {
      let clock = cache.clock
      let by_tick =
        cache.by_tick
        |> dict.delete(old)
        |> dict.insert(clock, key)
      let entries = dict.insert(cache.entries, key, #(value, clock))
      Ok(#(
        value,
        Lru(..cache, entries: entries, by_tick: by_tick, clock: clock + 1),
      ))
    }
    Error(Nil) -> Error(Nil)
  }
}

/// Inserts a key that is not present, evicting the least recent entry when full.
fn insert(cache: Lru, key: Int, value: Int) -> Lru {
  let cache = case dict.size(cache.entries) == cache.capacity {
    True -> evict(cache, cache.oldest)
    False -> cache
  }
  let clock = cache.clock
  Lru(
    ..cache,
    entries: dict.insert(cache.entries, key, #(value, clock)),
    by_tick: dict.insert(cache.by_tick, clock, key),
    clock: clock + 1,
  )
}

/// Counts `tick` up to the smallest live tick, then removes that entry.
fn evict(cache: Lru, tick: Int) -> Lru {
  case dict.get(cache.by_tick, tick) {
    Ok(key) ->
      Lru(
        ..cache,
        entries: dict.delete(cache.entries, key),
        by_tick: dict.delete(cache.by_tick, tick),
        oldest: tick + 1,
      )
    Error(Nil) -> evict(cache, tick + 1)
  }
}

/// Sums position * key over the live entries in increasing tick order.
fn checksum(cache: Lru) -> Int {
  let #(sum, _) =
    cache.by_tick
    |> dict.to_list
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.fold(#(0, 1), fn(acc, entry) {
      let #(sum, position) = acc
      #({ sum + position * entry.1 } % modulus, position + 1)
    })
  sum
}
