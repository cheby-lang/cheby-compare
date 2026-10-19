(* prime_sieve: the concurrent prime sieve, one Eio fiber per stage, joined by rendezvous streams. *)
open Eio.Std

(* Sends 2, 3, 4 and so on, forever. *)
let generate out =
  let rec loop i =
    Eio.Stream.add out i;
    loop (i + 1)
  in
  loop 2

(* Passes on the numbers from input that prime does not divide, forever. *)
let filter input out prime =
  let rec loop () =
    let m = Eio.Stream.take input in
    if m mod prime <> 0 then Eio.Stream.add out m;
    loop ()
  in
  loop ()

let () =
  let n = int_of_string Sys.argv.(1) in
  (* Shutdown option 2: every stage is a daemon fiber of one switch, so when the main fiber is *)
  (* done the switch cancels them all at once and waits for them. *)
  let last, sum =
    Eio_main.run @@ fun _env ->
    Switch.run @@ fun sw ->
    let ch = Eio.Stream.create 0 in
    Fiber.fork_daemon ~sw (fun () -> generate ch);
    let rec sieve i ch last sum =
      if i < n then begin
        let prime = Eio.Stream.take ch in
        let next = Eio.Stream.create 0 in
        Fiber.fork_daemon ~sw (fun () -> filter ch next prime);
        sieve (i + 1) next prime (sum + prime)
      end
      else (last, sum)
    in
    sieve 0 ch 0 0
  in
  Printf.printf "primes: %d\nlast: %d\nsum: %d\n" n last sum
