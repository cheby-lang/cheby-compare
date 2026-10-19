(* Binary-trees: allocates and walks many short-lived perfect binary trees. *)
(* The argument is the maximum depth n: a stretch tree of depth n + 1, a long-lived tree of *)
(* depth n, and 2^(n - d + 4) trees of each depth d = 4, 6, ..., n. A check counts the nodes. *)

type tree = Empty | Node of tree * tree

let min_depth = 4

(* Node (Empty, Empty) would be a structured constant: ocamlopt emits one static block and every
   leaf would share it. Hiding Empty behind opaque_identity makes each leaf a fresh allocation,
   as the SPEC requires (one node is one heap allocation, no sharing). *)
let empty = Sys.opaque_identity Empty

(* A perfect tree of depth d, built left subtree first. *)
let rec make d =
  if d = 0 then Node (empty, empty)
  else
    let left = make (d - 1) in
    let right = make (d - 1) in
    Node (left, right)

(* The number of nodes of t, by walking it. *)
let rec check = function
  | Empty -> 0
  | Node (left, right) -> 1 + check left + check right

let () =
  let n = int_of_string Sys.argv.(1) in
  let stretch_depth = n + 1 in
  Printf.printf "stretch tree of depth %d\t check: %d\n" stretch_depth
    (check (make stretch_depth));
  let long_lived = make n in
  let rec depths d =
    if d <= n then begin
      let iterations = 1 lsl (n - d + min_depth) in
      let rec loop i total =
        if i = 0 then total else loop (i - 1) (total + check (make d))
      in
      Printf.printf "%d\t trees of depth %d\t check: %d\n" iterations d
        (loop iterations 0);
      depths (d + 2)
    end
  in
  depths min_depth;
  Printf.printf "long lived tree of depth %d\t check: %d\n" n (check long_lived)
