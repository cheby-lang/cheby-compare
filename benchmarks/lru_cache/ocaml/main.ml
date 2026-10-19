(* LRU cache: a capacity-bounded cache under a skewed pseudo-random key *)
(* stream. The cache is a Hashtbl from key to node plus a doubly linked list *)
(* of mutable nodes. The list is circular around a sentinel node: the *)
(* sentinel's next is the head, the least recently used entry, and its prev *)
(* is the tail, the most recent. *)

let modulus = 1_000_000_007
let lehmer_m = 2_147_483_647
let lehmer_a = 48_271
let seed = 42
let hot_percent = 80
let key_space_factor = 16

type node = {
  mutable key : int;
  mutable value : int;
  mutable prev : node;
  mutable next : node;
}

type lru = { capacity : int; index : (int, node) Hashtbl.t; sentinel : node }

let create capacity =
  let rec sentinel = { key = -1; value = 0; prev = sentinel; next = sentinel } in
  { capacity; index = Hashtbl.create capacity; sentinel }

let unlink node =
  node.prev.next <- node.next;
  node.next.prev <- node.prev

let push_back lru node =
  let s = lru.sentinel in
  node.prev <- s.prev;
  node.next <- s;
  s.prev.next <- node;
  s.prev <- node

(* Returns the value of [key] and makes it the most recent, or [None] on a *)
(* miss. *)
let get lru key =
  match Hashtbl.find_opt lru.index key with
  | None -> None
  | Some node ->
      if lru.sentinel.prev != node then begin
        unlink node;
        push_back lru node
      end;
      Some node.value

(* Inserts a key that is not present, evicting the least recent entry when *)
(* full. *)
let insert lru key value =
  let node =
    if Hashtbl.length lru.index < lru.capacity then
      { key; value; prev = lru.sentinel; next = lru.sentinel }
    else begin
      let old = lru.sentinel.next in
      unlink old;
      Hashtbl.remove lru.index old.key;
      old.key <- key;
      old.value <- value;
      old
    end
  in
  push_back lru node;
  Hashtbl.replace lru.index key node

let () =
  let capacity = int_of_string Sys.argv.(1) in
  let ops = int_of_string Sys.argv.(2) in
  let hot = capacity in
  let cold = capacity * (key_space_factor - 1) in
  let cache = create capacity in
  let hits = ref 0 and misses = ref 0 and values = ref 0 in
  let state = ref seed in
  for _ = 1 to ops do
    state := !state * lehmer_a mod lehmer_m;
    let draw = !state / 100 in
    let key =
      if !state mod 100 < hot_percent then draw mod hot
      else hot + (draw mod cold)
    in
    match get cache key with
    | Some value ->
        incr hits;
        values := (!values + value) mod modulus
    | None ->
        insert cache key ((key * 2) + 1);
        incr misses
  done;
  let rec checksum acc position node =
    if node == cache.sentinel then acc
    else
      checksum
        ((acc + (position * node.key)) mod modulus)
        (position + 1) node.next
  in
  Printf.printf "hits %d\n" !hits;
  Printf.printf "misses %d\n" !misses;
  Printf.printf "values %d\n" !values;
  Printf.printf "checksum %d\n" (checksum 0 1 cache.sentinel.next)
