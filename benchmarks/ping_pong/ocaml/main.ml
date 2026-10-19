(* ping_pong: two systhreads exchange n messages over two synchronous Event channels. *)

(* Task B: answers each of the n values from ping with the value plus one on pong. *)
let echo n ping pong =
  for _ = 1 to n do
    let x = Event.sync (Event.receive ping) in
    Event.sync (Event.send pong (x + 1))
  done

let () =
  let n = int_of_string Sys.argv.(1) in
  let ping = Event.new_channel () in
  let pong = Event.new_channel () in
  let b = Thread.create (fun () -> echo n ping pong) () in
  let sum = ref 0 in
  for i = 1 to n do
    Event.sync (Event.send ping i);
    sum := !sum + Event.sync (Event.receive pong)
  done;
  Thread.join b;
  Printf.printf "%d\n%d\n" n !sum
