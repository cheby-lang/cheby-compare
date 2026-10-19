(* spawn_many: spawn n short Eio fibers in batches of [batch], join each batch and print the sum. *)
(* Each task is a fiber from Fiber.fork_promise in one switch per batch, joined by Promise.await_exn. *)
(* A task yields first, so its work runs after the spawn and the batch holds its tasks suspended. *)
open Eio.Std

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

(* A task: yields to the spawner at once, then computes its work when the scheduler resumes it. *)
let task index () =
  Fiber.yield ();
  work index

(* Forks one fiber per index in start .. start + count - 1, awaits them all, sums the results. *)
let spawn_and_join start count =
  Switch.run @@ fun sw ->
  let promises = Array.init count (fun j -> Fiber.fork_promise ~sw (task (start + j))) in
  Array.fold_left (fun sum p -> sum + Promise.await_exn p) 0 promises

let () =
  let n = int_of_string Sys.argv.(1) in
  let sum =
    Eio_main.run @@ fun _env ->
    let rec loop start sum =
      if start < n then
        loop (start + batch) (sum + spawn_and_join start (min batch (n - start)))
      else sum
    in
    loop 0 0
  in
  Printf.printf "tasks: %d\nsum: %d\n" n sum
