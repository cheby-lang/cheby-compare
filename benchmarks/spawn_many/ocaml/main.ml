(* spawn_many: spawn n short tasks in batches of [batch], join each batch and print the sum. *)
(* Each task is one systhread (Thread.create) that writes its own slot of the batch's array. *)

let batch = 1000
let rounds = 10
let modulus = 2147483647
let multiplier = 48271

(* The value of the task with this index: [rounds] MINSTD steps from index + 1. *)
let work index =
  let x = ref (index + 1) in
  for _ = 1 to rounds do
    x := !x * multiplier mod modulus
  done;
  !x

(* Spawns one thread per index in start .. start + count - 1, joins them all, sums the results. *)
let spawn_and_join start count =
  let results = Array.make count 0 in
  let threads =
    Array.init count (fun j ->
        Thread.create (fun () -> results.(j) <- work (start + j)) ())
  in
  Array.iter Thread.join threads;
  Array.fold_left ( + ) 0 results

let () =
  let n = int_of_string Sys.argv.(1) in
  let rec loop start sum =
    if start < n then
      loop (start + batch) (sum + spawn_and_join start (min batch (n - start)))
    else sum
  in
  let sum = loop 0 0 in
  Printf.printf "tasks: %d\nsum: %d\n" n sum
