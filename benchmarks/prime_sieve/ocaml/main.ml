(* prime_sieve: the concurrent prime sieve, one systhread per stage, connected by Event channels. *)

(* Sends 2, 3, 4 and so on, forever. *)
let generate out =
  let rec loop i =
    Event.sync (Event.send out i);
    loop (i + 1)
  in
  loop 2

(* Passes on the numbers from input that prime does not divide, forever. *)
let filter input out prime =
  let rec loop () =
    let m = Event.sync (Event.receive input) in
    if m mod prime <> 0 then Event.sync (Event.send out m);
    loop ()
  in
  loop ()

let () =
  let n = int_of_string Sys.argv.(1) in
  let ch = Event.new_channel () in
  ignore (Thread.create generate ch);
  let rec sieve i ch last sum =
    if i < n then begin
      let prime = Event.sync (Event.receive ch) in
      let next = Event.new_channel () in
      ignore (Thread.create (fun () -> filter ch next prime) ());
      sieve (i + 1) next prime (sum + prime)
    end
    else (last, sum)
  in
  let last, sum = sieve 0 ch 0 0 in
  Printf.printf "primes: %d\nlast: %d\nsum: %d\n" n last sum;
  (* Shutdown option 1: end the process with the stages still blocked, never joined. *)
  exit 0
